"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const client_1 = require("@prisma/client");
const express_1 = require("express");
const zod_1 = require("zod");
const api_error_1 = require("../../lib/api-error");
const http_1 = require("../../lib/http");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const query_1 = require("../../lib/query");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const accounting_service_1 = require("./accounting.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const accountSchema = zod_1.z.object({
    code: zod_1.z.string().min(1),
    name: zod_1.z.string().min(1),
    type: zod_1.z.nativeEnum(client_1.AccountType),
    active: zod_1.z.boolean().default(true),
});
const manualJournalSchema = zod_1.z.object({
    entryDate: zod_1.z.coerce.date().nullable().optional(),
    memo: zod_1.z.string().max(240).nullable().optional(),
    reference: zod_1.z.string().max(120).nullable().optional(),
    lines: zod_1.z
        .array(zod_1.z.object({
        accountId: zod_1.z.string().min(1),
        debit: zod_1.z.number().min(0).default(0),
        credit: zod_1.z.number().min(0).default(0),
        description: zod_1.z.string().max(240).nullable().optional(),
    }))
        .min(2),
});
// GET /accounting/accounts
router.get('/accounts', (0, authorize_1.requirePermission)('accounting.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    await prisma_1.prisma.$transaction((tx) => (0, accounting_service_1.ensureDefaultAccounts)(tx));
    const rows = await (0, accounting_service_1.trialBalance)(prisma_1.prisma);
    (0, http_1.ok)(res, rows.map((row) => ({
        id: row.accountId,
        code: row.code,
        name: row.name,
        type: row.type,
        debit: row.debit,
        credit: row.credit,
    })));
}));
// POST /accounting/accounts
router.post('/accounts', (0, authorize_1.requirePermission)('accounting.write'), (0, validate_1.validateBody)(accountSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const account = await prisma_1.prisma.account.create({ data: req.body });
    (0, http_1.created)(res, account);
}));
// GET /accounting/journal
router.get('/journal', (0, authorize_1.requirePermission)('accounting.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const paging = (0, http_1.getPaging)(req.query, 25);
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const search = (0, query_1.asString)(req.query.search);
    const where = {
        ...(from || to ? { entryDate: { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) } } : {}),
        ...(search
            ? {
                OR: [
                    { number: { contains: search, mode: 'insensitive' } },
                    { memo: { contains: search, mode: 'insensitive' } },
                    { reference: { contains: search, mode: 'insensitive' } },
                ],
            }
            : {}),
    };
    const [total, entries] = await Promise.all([
        prisma_1.prisma.journalEntry.count({ where }),
        prisma_1.prisma.journalEntry.findMany({
            where,
            orderBy: { entryDate: 'desc' },
            skip: paging.skip,
            take: paging.take,
            include: {
                user: { select: { id: true, name: true } },
                lines: { include: { account: { select: { id: true, code: true, name: true } } } },
            },
        }),
    ]);
    const data = entries.map((entry) => ({
        ...entry,
        lines: entry.lines.map((line) => ({
            ...line,
            debit: Number(line.debit),
            credit: Number(line.credit),
        })),
    }));
    (0, http_1.paginated)(res, data, total, paging);
}));
// GET /accounting/journal/:id
router.get('/journal/:id', (0, authorize_1.requirePermission)('accounting.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const entry = await prisma_1.prisma.journalEntry.findUnique({
        where: { id: req.params.id },
        include: {
            user: { select: { id: true, name: true } },
            lines: { include: { account: { select: { id: true, code: true, name: true, type: true } } } },
        },
    });
    if (!entry) {
        (0, http_1.ok)(res, null);
        return;
    }
    (0, http_1.ok)(res, {
        ...entry,
        lines: entry.lines.map((line) => ({
            ...line,
            debit: Number(line.debit),
            credit: Number(line.credit),
        })),
    });
}));
// GET /accounting/trial-balance
router.get('/trial-balance', (0, authorize_1.requirePermission)('accounting.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    await prisma_1.prisma.$transaction((tx) => (0, accounting_service_1.ensureDefaultAccounts)(tx));
    const rows = await (0, accounting_service_1.trialBalance)(prisma_1.prisma);
    const withBalance = rows.map((row) => {
        const raw = row.debit - row.credit;
        const balance = row.type === 'ASSET' || row.type === 'EXPENSE' ? raw : -raw;
        return {
            id: row.accountId,
            code: row.code,
            name: row.name,
            type: row.type,
            debit: row.debit,
            credit: row.credit,
            balance: (0, money_1.round2)(balance),
        };
    });
    (0, http_1.ok)(res, {
        rows: withBalance,
        totals: {
            debit: (0, money_1.round2)(withBalance.reduce((sum, row) => sum + row.debit, 0)),
            credit: (0, money_1.round2)(withBalance.reduce((sum, row) => sum + row.credit, 0)),
        },
    });
}));
// POST /accounting/journal — a manually entered double-entry journal entry.
router.post('/journal', (0, authorize_1.requirePermission)('accounting.write'), (0, validate_1.validateBody)(manualJournalSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const user = (0, authenticate_1.currentUser)(req);
    const body = req.body;
    const accounts = await prisma_1.prisma.account.findMany({
        where: { id: { in: body.lines.map((line) => line.accountId) } },
        select: { id: true, code: true },
    });
    const codeById = new Map(accounts.map((account) => [account.id, account.code]));
    let debitTotal = 0;
    let creditTotal = 0;
    const lines = body.lines.map((line) => {
        const code = codeById.get(line.accountId);
        if (!code) {
            throw api_error_1.ApiError.badRequest(`Unknown account "${line.accountId}"`, 'ACCOUNT_NOT_FOUND');
        }
        const debit = (0, money_1.round2)(line.debit ?? 0);
        const credit = (0, money_1.round2)(line.credit ?? 0);
        if (debit < 0 || credit < 0) {
            throw api_error_1.ApiError.badRequest('Amounts cannot be negative', 'INVALID_LINE');
        }
        if ((debit > 0) === (credit > 0)) {
            throw api_error_1.ApiError.badRequest('Each line needs either a debit or a credit, not both', 'INVALID_LINE');
        }
        debitTotal += debit;
        creditTotal += credit;
        return {
            accountCode: code,
            debit,
            credit,
            description: line.description ?? undefined,
        };
    });
    if ((0, money_1.round2)(debitTotal) <= 0) {
        throw api_error_1.ApiError.badRequest('A journal entry needs a positive amount', 'EMPTY_JOURNAL');
    }
    if (Math.abs((0, money_1.round2)(debitTotal) - (0, money_1.round2)(creditTotal)) > 0.01) {
        throw api_error_1.ApiError.badRequest(`Journal entry is not balanced (debits ${(0, money_1.round2)(debitTotal)} vs credits ${(0, money_1.round2)(creditTotal)})`, 'UNBALANCED_JOURNAL');
    }
    let entryId = null;
    await prisma_1.prisma.$transaction(async (tx) => {
        await (0, accounting_service_1.postJournal)(tx, {
            memo: body.memo ?? undefined,
            reference: body.reference ?? undefined,
            entryDate: body.entryDate ?? undefined,
            sourceType: 'MANUAL',
            userId: user.id,
            lines,
        });
        const latest = await tx.journalEntry.findFirst({
            where: { sourceType: 'MANUAL' },
            orderBy: { createdAt: 'desc' },
            select: { id: true },
        });
        entryId = latest?.id ?? null;
    });
    const entry = entryId
        ? await prisma_1.prisma.journalEntry.findUnique({
            where: { id: entryId },
            include: {
                user: { select: { id: true, name: true } },
                lines: { include: { account: { select: { id: true, code: true, name: true } } } },
            },
        })
        : null;
    (0, http_1.created)(res, entry
        ? {
            ...entry,
            lines: entry.lines.map((line) => ({
                ...line,
                debit: Number(line.debit),
                credit: Number(line.credit),
            })),
        }
        : null);
}));
// POST /accounting/journal/:id/reverse — reverse a manual entry only.
router.post('/journal/:id/reverse', (0, authorize_1.requirePermission)('accounting.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const user = (0, authenticate_1.currentUser)(req);
    const entry = await prisma_1.prisma.journalEntry.findUnique({
        where: { id: req.params.id },
        include: { lines: { include: { account: { select: { code: true } } } } },
    });
    if (!entry)
        throw api_error_1.ApiError.notFound('Journal entry not found');
    if (entry.sourceType !== 'MANUAL') {
        throw api_error_1.ApiError.badRequest('Only manual entries can be reversed', 'NOT_MANUAL');
    }
    if (entry.lines.length === 0) {
        throw api_error_1.ApiError.badRequest('This entry has no lines to reverse', 'NOT_MANUAL');
    }
    let reversalId = null;
    await prisma_1.prisma.$transaction(async (tx) => {
        await (0, accounting_service_1.postJournal)(tx, {
            memo: `Reversal of ${entry.number}`,
            reference: entry.reference ?? undefined,
            sourceType: 'MANUAL_REVERSAL',
            sourceId: entry.id,
            userId: user.id,
            lines: entry.lines.map((line) => ({
                accountCode: line.account.code,
                debit: Number(line.credit),
                credit: Number(line.debit),
                description: `Reversal · ${line.description ?? entry.number}`.slice(0, 240),
            })),
        });
        const latest = await tx.journalEntry.findFirst({
            where: { sourceType: 'MANUAL_REVERSAL', sourceId: entry.id },
            orderBy: { createdAt: 'desc' },
            select: { id: true },
        });
        reversalId = latest?.id ?? null;
    });
    const reversal = reversalId
        ? await prisma_1.prisma.journalEntry.findUnique({
            where: { id: reversalId },
            include: {
                user: { select: { id: true, name: true } },
                lines: { include: { account: { select: { id: true, code: true, name: true } } } },
            },
        })
        : null;
    (0, http_1.ok)(res, reversal
        ? {
            ...reversal,
            lines: reversal.lines.map((line) => ({
                ...line,
                debit: Number(line.debit),
                credit: Number(line.credit),
            })),
        }
        : null);
}));
// GET /accounting/income-statement
router.get('/income-statement', (0, authorize_1.requirePermission)('accounting.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    (0, http_1.ok)(res, await (0, accounting_service_1.buildIncomeStatement)(prisma_1.prisma, from, to));
}));
// GET /accounting/balance-sheet
router.get('/balance-sheet', (0, authorize_1.requirePermission)('accounting.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const asOf = (0, query_1.asDate)(req.query.asOf);
    (0, http_1.ok)(res, await (0, accounting_service_1.buildBalanceSheet)(prisma_1.prisma, asOf));
}));
exports.default = router;
//# sourceMappingURL=accounting.routes.js.map