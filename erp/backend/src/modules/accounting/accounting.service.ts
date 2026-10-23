import { AccountType } from '@prisma/client';
import { randomUUID } from 'crypto';
import { ApiError } from '../../lib/api-error';
import { round2 } from '../../lib/money';
import type { Tx } from '../../lib/prisma';
import { nextNumber, nextNumbers } from '../../lib/sequence';
import { getSettings } from '../../lib/settings';

/** Chart of accounts created automatically so the ledger always balances. */
export const DEFAULT_ACCOUNTS: { code: string; name: string; type: AccountType }[] = [
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

export const ACCOUNT = {
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
} as const;

export async function ensureDefaultAccounts(tx: Tx): Promise<void> {
  // One round-trip instead of one upsert per account. This runs on every
  // journal post, so keeping it cheap matters for bulk receipts.
  await tx.account.createMany({ data: DEFAULT_ACCOUNTS, skipDuplicates: true });
}

export interface JournalLineInput {
  accountCode: string;
  debit?: number;
  credit?: number;
  description?: string;
}

export interface JournalInput {
  memo?: string;
  reference?: string;
  sourceType?: string;
  sourceId?: string;
  userId?: string;
  entryDate?: Date;
  lines: JournalLineInput[];
}

/**
 * Posts a balanced double-entry journal entry. Silently ignores entries whose
 * lines are all zero, so callers can post unconditionally.
 */
export async function postJournal(tx: Tx, input: JournalInput): Promise<void> {
  const lines = input.lines
    .map((line) => ({
      accountCode: line.accountCode,
      debit: round2(line.debit ?? 0),
      credit: round2(line.credit ?? 0),
      description: line.description,
    }))
    .filter((line) => line.debit !== 0 || line.credit !== 0);

  if (lines.length === 0) return;

  const debitTotal = round2(lines.reduce((sum, line) => sum + line.debit, 0));
  const creditTotal = round2(lines.reduce((sum, line) => sum + line.credit, 0));
  if (Math.abs(debitTotal - creditTotal) > 0.01) {
    throw ApiError.badRequest(
      `Journal entry is not balanced (debits ${debitTotal} vs credits ${creditTotal})`,
      'UNBALANCED_JOURNAL',
    );
  }

  await ensureDefaultAccounts(tx);

  const accounts = await tx.account.findMany({
    where: { code: { in: lines.map((line) => line.accountCode) } },
    select: { id: true, code: true },
  });
  const accountIdByCode = new Map(accounts.map((account) => [account.code, account.id]));

  const settings = await getSettings(tx);
  const entryDate = input.entryDate ?? new Date();
  const number = await nextNumber(
    tx,
    'journal',
    settings.journalPrefix,
    entryDate,
    async (candidate) => (await tx.journalEntry.count({ where: { number: candidate } })) > 0,
  );

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
            throw ApiError.badRequest(`Unknown account code "${line.accountCode}"`, 'ACCOUNT_NOT_FOUND');
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
 * Posts many balanced journals in a handful of round-trips. Used by the bulk
 * collection receipt, where posting one journal per customer line used to cost
 * several hundred queries inside a single transaction.
 *
 * Each entry keeps its own number and `sourceType`/`sourceId`, so cancellation
 * and reporting work exactly like [postJournal].
 */
export async function postJournalBatch(tx: Tx, inputs: JournalInput[]): Promise<void> {
  const prepared = inputs
    .map((input) => ({
      input,
      entryDate: input.entryDate ?? new Date(),
      lines: input.lines
        .map((line) => ({
          accountCode: line.accountCode,
          debit: round2(line.debit ?? 0),
          credit: round2(line.credit ?? 0),
          description: line.description ?? null,
        }))
        .filter((line) => line.debit !== 0 || line.credit !== 0),
    }))
    .filter((entry) => entry.lines.length > 0);

  if (prepared.length === 0) return;

  for (const entry of prepared) {
    const debitTotal = round2(entry.lines.reduce((sum, line) => sum + line.debit, 0));
    const creditTotal = round2(entry.lines.reduce((sum, line) => sum + line.credit, 0));
    if (Math.abs(debitTotal - creditTotal) > 0.01) {
      throw ApiError.badRequest(
        `Journal entry is not balanced (debits ${debitTotal} vs credits ${creditTotal})`,
        'UNBALANCED_JOURNAL',
      );
    }
  }

  await ensureDefaultAccounts(tx);

  const codes = [...new Set(prepared.flatMap((entry) => entry.lines.map((line) => line.accountCode)))];
  const accounts = await tx.account.findMany({
    where: { code: { in: codes } },
    select: { id: true, code: true },
  });
  const accountIdByCode = new Map(accounts.map((account) => [account.code, account.id]));
  for (const code of codes) {
    if (!accountIdByCode.has(code)) {
      throw ApiError.badRequest(`Unknown account code "${code}"`, 'ACCOUNT_NOT_FOUND');
    }
  }

  const settings = await getSettings(tx);
  const numbers = new Array<string>(prepared.length);

  // Allocate per calendar year so the `PREFIX-YYYY-00001` shape stays intact.
  const byYear = new Map<number, number[]>();
  prepared.forEach((entry, index) => {
    const indexes = byYear.get(entry.entryDate.getFullYear()) ?? [];
    indexes.push(index);
    byYear.set(entry.entryDate.getFullYear(), indexes);
  });

  for (const [year, indexes] of byYear) {
    const allocated = await nextNumbers(
      tx,
      'journal',
      settings.journalPrefix,
      indexes.length,
      new Date(year, 0, 1),
      async (candidates) => {
        const rows = await tx.journalEntry.findMany({
          where: { number: { in: candidates } },
          select: { number: true },
        });
        return new Set(rows.map((row) => row.number));
      },
      async (candidate) =>
        (await tx.journalEntry.count({ where: { number: candidate } })) > 0,
    );
    indexes.forEach((index, offset) => {
      numbers[index] = allocated[offset];
    });
  }

  const entryData = prepared.map((entry, index) => ({
    id: randomUUID(),
    number: numbers[index],
    entryDate: entry.entryDate,
    memo: entry.input.memo ?? null,
    reference: entry.input.reference ?? null,
    sourceType: entry.input.sourceType ?? null,
    sourceId: entry.input.sourceId ?? null,
    userId: entry.input.userId ?? null,
  }));

  await tx.journalEntry.createMany({ data: entryData });

  const lineData = prepared.flatMap((entry, index) =>
    entry.lines.map((line) => ({
      id: randomUUID(),
      journalEntryId: entryData[index].id,
      accountId: accountIdByCode.get(line.accountCode)!,
      debit: line.debit,
      credit: line.credit,
      description: line.description,
    })),
  );

  if (lineData.length > 0) {
    await tx.journalLine.createMany({ data: lineData });
  }
}

export interface ReverseJournalInput {
  /** Source type of the original entry (e.g. "PAYMENT", "INVOICE"). */
  sourceType: string;
  sourceId: string;
  /** Source type recorded on the reversing entry. */
  reversalSourceType: string;
  memo: string;
  reference?: string;
  userId?: string;
  entryDate?: Date;
}

/**
 * Posts the exact reversal of the most recent entry posted for a source
 * document (looked up by `sourceType` + `sourceId`). Returns false when the
 * document has no journal entry (e.g. a draft invoice).
 */
export async function reverseJournalBySource(tx: Tx, input: ReverseJournalInput): Promise<boolean> {
  const entry = await tx.journalEntry.findFirst({
    where: { sourceType: input.sourceType, sourceId: input.sourceId },
    include: { lines: { include: { account: { select: { code: true } } } } },
    orderBy: { createdAt: 'desc' },
  });
  if (!entry) return false;

  await postJournal(tx, {
    memo: input.memo,
    reference: input.reference ?? entry.reference ?? undefined,
    sourceType: input.reversalSourceType,
    sourceId: input.sourceId,
    userId: input.userId,
    entryDate: input.entryDate ?? new Date(),
    lines: entry.lines.map((line) => ({
      accountCode: line.account.code,
      debit: round2(Number(line.credit)),
      credit: round2(Number(line.debit)),
      description: `Reversal · ${line.description ?? entry.memo ?? entry.number}`.slice(0, 240),
    })),
  });
  return true;
}

type TrialBalanceRow = {
  accountId: string;
  code: string;
  name: string;
  type: AccountType;
  debit: number;
  credit: number;
};

export async function trialBalance(tx: Tx): Promise<TrialBalanceRow[]> {
  const accounts = await tx.account.findMany({ orderBy: { code: 'asc' } });
  const grouped = await tx.journalLine.groupBy({
    by: ['accountId'],
    _sum: { debit: true, credit: true },
  });
  const byAccount = new Map(
    grouped.map((row) => [row.accountId, { debit: Number(row._sum.debit ?? 0), credit: Number(row._sum.credit ?? 0) }]),
  );

  return accounts.map((account) => {
    const sums = byAccount.get(account.id) ?? { debit: 0, credit: 0 };
    return {
      accountId: account.id,
      code: account.code,
      name: account.name,
      type: account.type,
      debit: round2(sums.debit),
      credit: round2(sums.credit),
    };
  });
}

/** Like [trialBalance] but limited to an optional entry-date range. */
export async function accountBalances(
  tx: Tx,
  from?: Date,
  to?: Date,
): Promise<TrialBalanceRow[]> {
  const accounts = await tx.account.findMany({ orderBy: { code: 'asc' } });
  const grouped = await tx.journalLine.groupBy({
    by: ['accountId'],
    where:
      from || to
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
  const byAccount = new Map(
    grouped.map((row) => [
      row.accountId,
      { debit: Number(row._sum.debit ?? 0), credit: Number(row._sum.credit ?? 0) },
    ]),
  );

  return accounts.map((account) => {
    const sums = byAccount.get(account.id) ?? { debit: 0, credit: 0 };
    return {
      accountId: account.id,
      code: account.code,
      name: account.name,
      type: account.type,
      debit: round2(sums.debit),
      credit: round2(sums.credit),
    };
  });
}

export interface StatementRow {
  accountId: string;
  code: string;
  name: string;
  amount: number;
}

export interface IncomeStatementReport {
  from: string | null;
  to: string | null;
  revenue: StatementRow[];
  expenses: StatementRow[];
  totals: { revenue: number; expenses: number; netProfit: number };
}

/** Revenue minus expenses over a period, straight from the ledger. */
export async function buildIncomeStatement(
  tx: Tx,
  from?: Date,
  to?: Date,
): Promise<IncomeStatementReport> {
  const rows = await accountBalances(tx, from, to);

  const revenue = rows
    .filter((row) => row.type === 'REVENUE')
    .map((row) => ({
      accountId: row.accountId,
      code: row.code,
      name: row.name,
      amount: round2(row.credit - row.debit),
    }))
    .filter((row) => row.amount !== 0);

  const expenses = rows
    .filter((row) => row.type === 'EXPENSE')
    .map((row) => ({
      accountId: row.accountId,
      code: row.code,
      name: row.name,
      amount: round2(row.debit - row.credit),
    }))
    .filter((row) => row.amount !== 0);

  const revenueTotal = round2(revenue.reduce((sum, row) => sum + row.amount, 0));
  const expenseTotal = round2(expenses.reduce((sum, row) => sum + row.amount, 0));

  return {
    from: from ? from.toISOString() : null,
    to: to ? to.toISOString() : null,
    revenue,
    expenses,
    totals: {
      revenue: revenueTotal,
      expenses: expenseTotal,
      netProfit: round2(revenueTotal - expenseTotal),
    },
  };
}

export interface BalanceSheetReport {
  asOf: string | null;
  assets: StatementRow[];
  liabilities: StatementRow[];
  equity: StatementRow[];
  totals: {
    assets: number;
    liabilities: number;
    equity: number;
    netProfit: number;
    liabilitiesAndEquity: number;
    balanced: boolean;
  };
}

/**
 * Assets / liabilities / equity balances as of a date. Retained earnings are
 * the cumulative revenue minus expenses, so the sheet always balances.
 */
export async function buildBalanceSheet(tx: Tx, asOf?: Date): Promise<BalanceSheetReport> {
  const rows = await accountBalances(tx, undefined, asOf);

  const toRows = (type: AccountType, debitPositive: boolean): StatementRow[] =>
    rows
      .filter((row) => row.type === type)
      .map((row) => ({
        accountId: row.accountId,
        code: row.code,
        name: row.name,
        amount: round2(debitPositive ? row.debit - row.credit : row.credit - row.debit),
      }))
      .filter((row) => row.amount !== 0);

  const assets = toRows('ASSET', true);
  const liabilities = toRows('LIABILITY', false);
  const equity = toRows('EQUITY', false);

  const assetsTotal = round2(assets.reduce((sum, row) => sum + row.amount, 0));
  const liabilitiesTotal = round2(liabilities.reduce((sum, row) => sum + row.amount, 0));
  const equityTotal = round2(equity.reduce((sum, row) => sum + row.amount, 0));

  const revenueTotal = round2(
    rows
      .filter((row) => row.type === 'REVENUE')
      .reduce((sum, row) => sum + (row.credit - row.debit), 0),
  );
  const expenseTotal = round2(
    rows
      .filter((row) => row.type === 'EXPENSE')
      .reduce((sum, row) => sum + (row.debit - row.credit), 0),
  );
  const netProfit = round2(revenueTotal - expenseTotal);
  const liabilitiesAndEquity = round2(liabilitiesTotal + equityTotal + netProfit);

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
