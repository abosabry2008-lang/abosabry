import { AccountType } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, getPaging, ok, paginated } from '../../lib/http';
import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { asDate, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import {
  buildBalanceSheet,
  buildIncomeStatement,
  ensureDefaultAccounts,
  postJournal,
  trialBalance,
} from './accounting.service';

const router = Router();
router.use(authenticate);

const accountSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  type: z.nativeEnum(AccountType),
  active: z.boolean().default(true),
});

const manualJournalSchema = z.object({
  entryDate: z.coerce.date().nullable().optional(),
  memo: z.string().max(240).nullable().optional(),
  reference: z.string().max(120).nullable().optional(),
  lines: z
    .array(
      z.object({
        accountId: z.string().min(1),
        debit: z.number().min(0).default(0),
        credit: z.number().min(0).default(0),
        description: z.string().max(240).nullable().optional(),
      }),
    )
    .min(2),
});

// GET /accounting/accounts
router.get(
  '/accounts',
  requirePermission('accounting.read'),
  asyncHandler(async (req, res) => {
    await prisma.$transaction((tx) => ensureDefaultAccounts(tx));
    const type = asString(req.query.type);
    const rows = (await trialBalance(prisma)).filter(
      (row) => !type || row.type === type,
    );
    ok(
      res,
      rows.map((row) => ({
        id: row.accountId,
        code: row.code,
        name: row.name,
        type: row.type,
        debit: row.debit,
        credit: row.credit,
      })),
    );
  }),
);

// POST /accounting/accounts
router.post(
  '/accounts',
  requirePermission('accounting.write'),
  validateBody(accountSchema),
  asyncHandler(async (req, res) => {
    const account = await prisma.account.create({ data: req.body });
    created(res, account);
  }),
);

// GET /accounting/journal
router.get(
  '/journal',
  requirePermission('accounting.read'),
  asyncHandler(async (req, res) => {
    const paging = getPaging(req.query as Record<string, unknown>, 25);
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const search = asString(req.query.search);

    const where = {
      ...(from || to ? { entryDate: { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) } } : {}),
      ...(search
        ? {
            OR: [
              { number: { contains: search, mode: 'insensitive' as const } },
              { memo: { contains: search, mode: 'insensitive' as const } },
              { reference: { contains: search, mode: 'insensitive' as const } },
            ],
          }
        : {}),
    };

    const [total, entries] = await Promise.all([
      prisma.journalEntry.count({ where }),
      prisma.journalEntry.findMany({
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

    paginated(res, data, total, paging);
  }),
);

// GET /accounting/journal/:id
router.get(
  '/journal/:id',
  requirePermission('accounting.read'),
  asyncHandler(async (req, res) => {
    const entry = await prisma.journalEntry.findUnique({
      where: { id: req.params.id },
      include: {
        user: { select: { id: true, name: true } },
        lines: { include: { account: { select: { id: true, code: true, name: true, type: true } } } },
      },
    });
    if (!entry) {
      ok(res, null);
      return;
    }
    ok(res, {
      ...entry,
      lines: entry.lines.map((line) => ({
        ...line,
        debit: Number(line.debit),
        credit: Number(line.credit),
      })),
    });
  }),
);

// GET /accounting/trial-balance
router.get(
  '/trial-balance',
  requirePermission('accounting.read'),
  asyncHandler(async (_req, res) => {
    await prisma.$transaction((tx) => ensureDefaultAccounts(tx));
    const rows = await trialBalance(prisma);

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
        balance: round2(balance),
      };
    });

    ok(res, {
      rows: withBalance,
      totals: {
        debit: round2(withBalance.reduce((sum, row) => sum + row.debit, 0)),
        credit: round2(withBalance.reduce((sum, row) => sum + row.credit, 0)),
      },
    });
  }),
);

// POST /accounting/journal — a manually entered double-entry journal entry.
router.post(
  '/journal',
  requirePermission('accounting.write'),
  validateBody(manualJournalSchema),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    const body = req.body as z.infer<typeof manualJournalSchema>;

    const accounts = await prisma.account.findMany({
      where: { id: { in: body.lines.map((line) => line.accountId) } },
      select: { id: true, code: true },
    });
    const codeById = new Map(accounts.map((account) => [account.id, account.code]));

    let debitTotal = 0;
    let creditTotal = 0;
    const lines = body.lines.map((line) => {
      const code = codeById.get(line.accountId);
      if (!code) {
        throw ApiError.badRequest(`Unknown account "${line.accountId}"`, 'ACCOUNT_NOT_FOUND');
      }
      const debit = round2(line.debit ?? 0);
      const credit = round2(line.credit ?? 0);
      if (debit < 0 || credit < 0) {
        throw ApiError.badRequest('Amounts cannot be negative', 'INVALID_LINE');
      }
      if ((debit > 0) === (credit > 0)) {
        throw ApiError.badRequest(
          'Each line needs either a debit or a credit, not both',
          'INVALID_LINE',
        );
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

    if (round2(debitTotal) <= 0) {
      throw ApiError.badRequest('A journal entry needs a positive amount', 'EMPTY_JOURNAL');
    }
    if (Math.abs(round2(debitTotal) - round2(creditTotal)) > 0.01) {
      throw ApiError.badRequest(
        `Journal entry is not balanced (debits ${round2(debitTotal)} vs credits ${round2(creditTotal)})`,
        'UNBALANCED_JOURNAL',
      );
    }

    let entryId: string | null = null;
    await prisma.$transaction(async (tx) => {
      await postJournal(tx, {
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
      ? await prisma.journalEntry.findUnique({
          where: { id: entryId },
          include: {
            user: { select: { id: true, name: true } },
            lines: { include: { account: { select: { id: true, code: true, name: true } } } },
          },
        })
      : null;

    created(
      res,
      entry
        ? {
            ...entry,
            lines: entry.lines.map((line) => ({
              ...line,
              debit: Number(line.debit),
              credit: Number(line.credit),
            })),
          }
        : null,
    );
  }),
);

// POST /accounting/journal/:id/reverse — reverse a manual entry only.
router.post(
  '/journal/:id/reverse',
  requirePermission('accounting.write'),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    const entry = await prisma.journalEntry.findUnique({
      where: { id: req.params.id },
      include: { lines: { include: { account: { select: { code: true } } } } },
    });
    if (!entry) throw ApiError.notFound('Journal entry not found');
    if (entry.sourceType !== 'MANUAL') {
      throw ApiError.badRequest('Only manual entries can be reversed', 'NOT_MANUAL');
    }
    if (entry.lines.length === 0) {
      throw ApiError.badRequest('This entry has no lines to reverse', 'NOT_MANUAL');
    }

    let reversalId: string | null = null;
    await prisma.$transaction(async (tx) => {
      await postJournal(tx, {
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
      ? await prisma.journalEntry.findUnique({
          where: { id: reversalId },
          include: {
            user: { select: { id: true, name: true } },
            lines: { include: { account: { select: { id: true, code: true, name: true } } } },
          },
        })
      : null;

    ok(
      res,
      reversal
        ? {
            ...reversal,
            lines: reversal.lines.map((line) => ({
              ...line,
              debit: Number(line.debit),
              credit: Number(line.credit),
            })),
          }
        : null,
    );
  }),
);

// GET /accounting/income-statement
router.get(
  '/income-statement',
  requirePermission('accounting.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    ok(res, await buildIncomeStatement(prisma, from, to));
  }),
);

// GET /accounting/balance-sheet
router.get(
  '/balance-sheet',
  requirePermission('accounting.read'),
  asyncHandler(async (req, res) => {
    const asOf = asDate(req.query.asOf);
    ok(res, await buildBalanceSheet(prisma, asOf));
  }),
);

export default router;
