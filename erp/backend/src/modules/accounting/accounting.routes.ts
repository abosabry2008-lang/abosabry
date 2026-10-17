import { AccountType } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, created, getPaging, ok, paginated } from '../../lib/http';
import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { asDate, asString } from '../../lib/query';
import { authenticate } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import { ensureDefaultAccounts, trialBalance } from './accounting.service';

const router = Router();
router.use(authenticate);

const accountSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  type: z.nativeEnum(AccountType),
  active: z.boolean().default(true),
});

// GET /accounting/accounts
router.get(
  '/accounts',
  requirePermission('accounting.read'),
  asyncHandler(async (_req, res) => {
    await prisma.$transaction((tx) => ensureDefaultAccounts(tx));
    const rows = await trialBalance(prisma);
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

export default router;
