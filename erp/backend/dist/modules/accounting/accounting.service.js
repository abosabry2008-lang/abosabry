"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ACCOUNT = exports.DEFAULT_ACCOUNTS = void 0;
exports.ensureDefaultAccounts = ensureDefaultAccounts;
exports.postJournal = postJournal;
exports.reverseJournalBySource = reverseJournalBySource;
exports.trialBalance = trialBalance;
exports.accountBalances = accountBalances;
exports.buildIncomeStatement = buildIncomeStatement;
exports.buildBalanceSheet = buildBalanceSheet;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const sequence_1 = require("../../lib/sequence");
const settings_1 = require("../../lib/settings");
/** Chart of accounts created automatically so the ledger always balances. */
exports.DEFAULT_ACCOUNTS = [
    { code: '1000', name: 'Cash', type: 'ASSET' },
    { code: '1010', name: 'Bank', type: 'ASSET' },
    { code: '1100', name: 'Accounts Receivable', type: 'ASSET' },
    { code: '1200', name: 'Inventory', type: 'ASSET' },
    { code: '1300', name: 'Tax Receivable', type: 'ASSET' },
    { code: '2000', name: 'Accounts Payable', type: 'LIABILITY' },
    { code: '2100', name: 'Tax Payable', type: 'LIABILITY' },
    { code: '3000', name: "Owner's Equity", type: 'EQUITY' },
    { code: '4000', name: 'Sales Revenue', type: 'REVENUE' },
    { code: '5000', name: 'Cost of Goods Sold', type: 'EXPENSE' },
    { code: '6000', name: 'Operating Expenses', type: 'EXPENSE' },
    { code: '7000', name: 'Settlements & Adjustments', type: 'EQUITY' },
];
exports.ACCOUNT = {
    CASH: '1000',
    BANK: '1010',
    RECEIVABLE: '1100',
    INVENTORY: '1200',
    TAX_RECEIVABLE: '1300',
    PAYABLE: '2000',
    TAX_PAYABLE: '2100',
    EQUITY: '3000',
    REVENUE: '4000',
    COGS: '5000',
    EXPENSE: '6000',
    SETTLEMENT: '7000',
};
async function ensureDefaultAccounts(tx) {
    for (const account of exports.DEFAULT_ACCOUNTS) {
        await tx.account.upsert({
            where: { code: account.code },
            create: account,
            update: {},
        });
    }
}
/**
 * Posts a balanced double-entry journal entry. Silently ignores entries whose
 * lines are all zero, so callers can post unconditionally.
 */
async function postJournal(tx, input) {
    const lines = input.lines
        .map((line) => ({
        accountCode: line.accountCode,
        debit: (0, money_1.round2)(line.debit ?? 0),
        credit: (0, money_1.round2)(line.credit ?? 0),
        description: line.description,
    }))
        .filter((line) => line.debit !== 0 || line.credit !== 0);
    if (lines.length === 0)
        return;
    const debitTotal = (0, money_1.round2)(lines.reduce((sum, line) => sum + line.debit, 0));
    const creditTotal = (0, money_1.round2)(lines.reduce((sum, line) => sum + line.credit, 0));
    if (Math.abs(debitTotal - creditTotal) > 0.01) {
        throw api_error_1.ApiError.badRequest(`Journal entry is not balanced (debits ${debitTotal} vs credits ${creditTotal})`, 'UNBALANCED_JOURNAL');
    }
    await ensureDefaultAccounts(tx);
    const accounts = await tx.account.findMany({
        where: { code: { in: lines.map((line) => line.accountCode) } },
        select: { id: true, code: true },
    });
    const accountIdByCode = new Map(accounts.map((account) => [account.code, account.id]));
    const settings = await (0, settings_1.getSettings)(tx);
    const entryDate = input.entryDate ?? new Date();
    const number = await (0, sequence_1.nextNumber)(tx, 'journal', settings.journalPrefix, entryDate);
    await tx.journalEntry.create({
        data: {
            number,
            entryDate,
            memo: input.memo,
            reference: input.reference,
            sourceType: input.sourceType,
            sourceId: input.sourceId,
            userId: input.userId,
            lines: {
                create: lines.map((line) => {
                    const accountId = accountIdByCode.get(line.accountCode);
                    if (!accountId) {
                        throw api_error_1.ApiError.badRequest(`Unknown account code "${line.accountCode}"`, 'ACCOUNT_NOT_FOUND');
                    }
                    return {
                        accountId,
                        debit: line.debit,
                        credit: line.credit,
                        description: line.description,
                    };
                }),
            },
        },
    });
}
/**
 * Posts the exact reversal of the most recent entry posted for a source
 * document (looked up by `sourceType` + `sourceId`). Returns false when the
 * document has no journal entry (e.g. a draft invoice).
 */
async function reverseJournalBySource(tx, input) {
    const entry = await tx.journalEntry.findFirst({
        where: { sourceType: input.sourceType, sourceId: input.sourceId },
        include: { lines: { include: { account: { select: { code: true } } } } },
        orderBy: { createdAt: 'desc' },
    });
    if (!entry)
        return false;
    await postJournal(tx, {
        memo: input.memo,
        reference: input.reference ?? entry.reference ?? undefined,
        sourceType: input.reversalSourceType,
        sourceId: input.sourceId,
        userId: input.userId,
        entryDate: input.entryDate ?? new Date(),
        lines: entry.lines.map((line) => ({
            accountCode: line.account.code,
            debit: (0, money_1.round2)(Number(line.credit)),
            credit: (0, money_1.round2)(Number(line.debit)),
            description: `Reversal · ${line.description ?? entry.memo ?? entry.number}`.slice(0, 240),
        })),
    });
    return true;
}
async function trialBalance(tx) {
    const accounts = await tx.account.findMany({ orderBy: { code: 'asc' } });
    const grouped = await tx.journalLine.groupBy({
        by: ['accountId'],
        _sum: { debit: true, credit: true },
    });
    const byAccount = new Map(grouped.map((row) => [row.accountId, { debit: Number(row._sum.debit ?? 0), credit: Number(row._sum.credit ?? 0) }]));
    return accounts.map((account) => {
        const sums = byAccount.get(account.id) ?? { debit: 0, credit: 0 };
        return {
            accountId: account.id,
            code: account.code,
            name: account.name,
            type: account.type,
            debit: (0, money_1.round2)(sums.debit),
            credit: (0, money_1.round2)(sums.credit),
        };
    });
}
/** Like [trialBalance] but limited to an optional entry-date range. */
async function accountBalances(tx, from, to) {
    const accounts = await tx.account.findMany({ orderBy: { code: 'asc' } });
    const grouped = await tx.journalLine.groupBy({
        by: ['accountId'],
        where: from || to
            ? {
                journalEntry: {
                    entryDate: {
                        ...(from ? { gte: from } : {}),
                        ...(to ? { lte: to } : {}),
                    },
                },
            }
            : {},
        _sum: { debit: true, credit: true },
    });
    const byAccount = new Map(grouped.map((row) => [
        row.accountId,
        { debit: Number(row._sum.debit ?? 0), credit: Number(row._sum.credit ?? 0) },
    ]));
    return accounts.map((account) => {
        const sums = byAccount.get(account.id) ?? { debit: 0, credit: 0 };
        return {
            accountId: account.id,
            code: account.code,
            name: account.name,
            type: account.type,
            debit: (0, money_1.round2)(sums.debit),
            credit: (0, money_1.round2)(sums.credit),
        };
    });
}
/** Revenue minus expenses over a period, straight from the ledger. */
async function buildIncomeStatement(tx, from, to) {
    const rows = await accountBalances(tx, from, to);
    const revenue = rows
        .filter((row) => row.type === 'REVENUE')
        .map((row) => ({
        accountId: row.accountId,
        code: row.code,
        name: row.name,
        amount: (0, money_1.round2)(row.credit - row.debit),
    }))
        .filter((row) => row.amount !== 0);
    const expenses = rows
        .filter((row) => row.type === 'EXPENSE')
        .map((row) => ({
        accountId: row.accountId,
        code: row.code,
        name: row.name,
        amount: (0, money_1.round2)(row.debit - row.credit),
    }))
        .filter((row) => row.amount !== 0);
    const revenueTotal = (0, money_1.round2)(revenue.reduce((sum, row) => sum + row.amount, 0));
    const expenseTotal = (0, money_1.round2)(expenses.reduce((sum, row) => sum + row.amount, 0));
    return {
        from: from ? from.toISOString() : null,
        to: to ? to.toISOString() : null,
        revenue,
        expenses,
        totals: {
            revenue: revenueTotal,
            expenses: expenseTotal,
            netProfit: (0, money_1.round2)(revenueTotal - expenseTotal),
        },
    };
}
/**
 * Assets / liabilities / equity balances as of a date. Retained earnings are
 * the cumulative revenue minus expenses, so the sheet always balances.
 */
async function buildBalanceSheet(tx, asOf) {
    const rows = await accountBalances(tx, undefined, asOf);
    const toRows = (type, debitPositive) => rows
        .filter((row) => row.type === type)
        .map((row) => ({
        accountId: row.accountId,
        code: row.code,
        name: row.name,
        amount: (0, money_1.round2)(debitPositive ? row.debit - row.credit : row.credit - row.debit),
    }))
        .filter((row) => row.amount !== 0);
    const assets = toRows('ASSET', true);
    const liabilities = toRows('LIABILITY', false);
    const equity = toRows('EQUITY', false);
    const assetsTotal = (0, money_1.round2)(assets.reduce((sum, row) => sum + row.amount, 0));
    const liabilitiesTotal = (0, money_1.round2)(liabilities.reduce((sum, row) => sum + row.amount, 0));
    const equityTotal = (0, money_1.round2)(equity.reduce((sum, row) => sum + row.amount, 0));
    const revenueTotal = (0, money_1.round2)(rows
        .filter((row) => row.type === 'REVENUE')
        .reduce((sum, row) => sum + (row.credit - row.debit), 0));
    const expenseTotal = (0, money_1.round2)(rows
        .filter((row) => row.type === 'EXPENSE')
        .reduce((sum, row) => sum + (row.debit - row.credit), 0));
    const netProfit = (0, money_1.round2)(revenueTotal - expenseTotal);
    const liabilitiesAndEquity = (0, money_1.round2)(liabilitiesTotal + equityTotal + netProfit);
    return {
        asOf: asOf ? asOf.toISOString() : null,
        assets,
        liabilities,
        equity,
        totals: {
            assets: assetsTotal,
            liabilities: liabilitiesTotal,
            equity: equityTotal,
            netProfit,
            liabilitiesAndEquity,
            balanced: Math.abs(assetsTotal - liabilitiesAndEquity) < 0.01,
        },
    };
}
//# sourceMappingURL=accounting.service.js.map