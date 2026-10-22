import { CashBoxType, Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, created, getPaging, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asBool, asDate, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission, requireAdmin } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import {
  cancelCollection,
  collectionInclude,
  createCollection,
} from '../payments/payments.service';
import {
  buildCashBoxStatement,
  cancelTransfer,
  createCashBox,
  createTransfer,
  deleteCashBox,
  getCashBox,
  inclusiveEnd,
  listCashBoxes,
  listTransfers,
  updateCashBox,
  updateTransfer,
} from './treasury.service';

const router = Router();
router.use(authenticate);

const boxSchema = z.object({
  code: z.string().min(1).max(20),
  name: z.string().min(1).max(120),
  type: z.nativeEnum(CashBoxType).optional(),
  openingBalance: z.number().optional(),
  active: z.boolean().optional(),
  isDefault: z.boolean().optional(),
});

const boxUpdateSchema = boxSchema.partial();

const transferSchema = z.object({
  fromBoxId: z.string().min(1),
  toBoxId: z.string().min(1),
  amount: z.number().positive(),
  exchangeRate: z.number().positive().optional(),
  reference: z.string().nullable().optional(),
  note: z.string().nullable().optional(),
  transferDate: z.coerce.date().nullable().optional(),
});

const transferUpdateSchema = z.object({
  amount: z.number().positive().optional(),
  reference: z.string().nullable().optional(),
  note: z.string().nullable().optional(),
  transferDate: z.coerce.date().nullable().optional(),
});

const collectionSchema = z.object({
  cashBoxId: z.string().nullable().optional(),
  salespersonId: z.string().nullable().optional(),
  collectedAt: z.coerce.date().nullable().optional(),
  reference: z.string().nullable().optional(),
  note: z.string().nullable().optional(),
  lines: z
    .array(
      z.object({
        customerId: z.string().nullable().optional(),
        invoiceId: z.string().nullable().optional(),
        cashBoxId: z.string().nullable().optional(),
        amount: z.number().positive(),
        note: z.string().nullable().optional(),
      }),
    )
    .min(1),
});

// --- serializers ------------------------------------------------------------

interface BoxMoney {
  openingBalance: unknown;
  balance?: unknown;
}

const serializeBox = <T extends BoxMoney>(box: T) => ({
  ...box,
  openingBalance: Number(box.openingBalance),
  ...(box.balance !== undefined ? { balance: Number(box.balance) } : {}),
});

interface TransferMoney {
  amount: unknown;
  exchangeRate: unknown;
}

const serializeTransfer = <T extends TransferMoney>(transfer: T) => ({
  ...transfer,
  amount: Number(transfer.amount),
  exchangeRate: Number(transfer.exchangeRate),
});

interface CollectionMoney {
  total: unknown;
  lines: { amount: unknown; invoice: { total: unknown; balance: unknown } | null }[];
  payments: { amount: unknown }[];
}

const serializeCollection = <T extends CollectionMoney>(voucher: T) => ({
  ...voucher,
  total: Number(voucher.total),
  lines: voucher.lines.map((line) => ({
    ...line,
    amount: Number(line.amount),
    invoice: line.invoice
      ? { ...line.invoice, total: Number(line.invoice.total), balance: Number(line.invoice.balance) }
      : null,
  })),
  payments: voucher.payments.map((payment) => ({ ...payment, amount: Number(payment.amount) })),
});

// --- cash boxes -------------------------------------------------------------

router.get(
  '/boxes',
  requirePermission('treasury.read'),
  asyncHandler(async (_req, res) => {
    const boxes = await listCashBoxes();
    ok(res, boxes.map(serializeBox));
  }),
);

router.post(
  '/boxes',
  requirePermission('treasury.write'),
  validateBody(boxSchema),
  asyncHandler(async (req, res) => {
    const box = await createCashBox(req.body, currentUser(req).id);
    created(res, serializeBox(box));
  }),
);

router.get(
  '/boxes/:id',
  requirePermission('treasury.read'),
  asyncHandler(async (req, res) => {
    const box = await getCashBox(req.params.id);
    ok(res, serializeBox(box));
  }),
);

router.patch(
  '/boxes/:id',
  requirePermission('treasury.write'),
  validateBody(boxUpdateSchema),
  asyncHandler(async (req, res) => {
    const box = await updateCashBox(req.params.id, req.body, currentUser(req).id);
    ok(res, serializeBox(box));
  }),
);

router.delete(
  '/boxes/:id',
  requirePermission('treasury.write'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const result = await deleteCashBox(req.params.id);
    ok(res, result);
  }),
);

router.get(
  '/boxes/:id/statement',
  requirePermission('treasury.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const statement = await buildCashBoxStatement(req.params.id, from, to);
    ok(res, statement);
  }),
);

// --- transfers --------------------------------------------------------------

router.get(
  '/transfers',
  requirePermission('treasury.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const boxId = asString(query.boxId);
    const from = asDate(query.from);
    const to = asDate(query.to);

    // Paged mode: used by the treasury "التحويلات" tab for lazy loading.
    if (asBool(query.paged) === true) {
      const paging = getPaging(query, 25);
      const result = await listTransfers({
        boxId,
        from,
        to,
        limit: paging.take,
        skip: paging.skip,
        includeCancelled: asBool(query.includeCancelled) === true,
        paged: true,
      });
      paginated(res, result.items.map(serializeTransfer), result.total, paging);
      return;
    }

    const transfers = await listTransfers({ boxId, from, to });
    ok(res, transfers.map(serializeTransfer));
  }),
);

router.post(
  '/transfers',
  requirePermission('treasury.write'),
  validateBody(transferSchema),
  asyncHandler(async (req, res) => {
    const transfer = await createTransfer({ ...req.body, userId: currentUser(req).id });
    created(res, serializeTransfer(transfer));
  }),
);

router.patch(
  '/transfers/:id',
  requirePermission('treasury.write'),
  validateBody(transferUpdateSchema),
  asyncHandler(async (req, res) => {
    const transfer = await updateTransfer(req.params.id, req.body);
    ok(res, serializeTransfer(transfer));
  }),
);

router.post(
  '/transfers/:id/cancel',
  requirePermission('treasury.write'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const transfer = await cancelTransfer(req.params.id, currentUser(req).id);
    ok(res, serializeTransfer(transfer));
  }),
);

// --- agent collection receipts ---------------------------------------------

router.get(
  '/collections',
  requirePermission('payments.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 25);
    const includeCancelled = asBool(query.includeCancelled) === true;
    const salespersonId = asString(query.salespersonId);
    const customerId = asString(query.customerId);
    const from = asDate(query.from);
    const to = asDate(query.to);
    const toBound = to ? inclusiveEnd(to) : undefined;

    const where: Prisma.CollectionVoucherWhereInput = {};
    if (!includeCancelled) where.cancelledAt = null;
    if (salespersonId) where.salespersonId = salespersonId;
    if (customerId) where.lines = { some: { customerId } };
    if (from || toBound) {
      where.collectedAt = { ...(from ? { gte: from } : {}), ...(toBound ? { lte: toBound } : {}) };
    }

    const [total, vouchers] = await Promise.all([
      prisma.collectionVoucher.count({ where }),
      prisma.collectionVoucher.findMany({
        where,
        include: collectionInclude,
        orderBy: [{ collectedAt: 'desc' }, { createdAt: 'desc' }],
        skip: paging.skip,
        take: paging.take,
      }),
    ]);

    paginated(res, vouchers.map(serializeCollection), total, paging);
  }),
);

router.post(
  '/collections',
  requirePermission('payments.write'),
  validateBody(collectionSchema),
  asyncHandler(async (req, res) => {
    const voucher = await createCollection({ ...req.body, userId: currentUser(req).id });
    created(res, serializeCollection(voucher));
  }),
);

router.get(
  '/collections/:id',
  requirePermission('payments.read'),
  asyncHandler(async (req, res) => {
    const voucher = await prisma.collectionVoucher.findUnique({
      where: { id: req.params.id },
      include: collectionInclude,
    });
    if (!voucher) {
      res.status(404).json({ error: { message: 'Collection receipt not found', code: 'NOT_FOUND' } });
      return;
    }
    ok(res, serializeCollection(voucher));
  }),
);

router.post(
  '/collections/:id/cancel',
  requirePermission('treasury.write'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const voucher = await cancelCollection(req.params.id, currentUser(req).id);
    ok(res, serializeCollection(voucher));
  }),
);

export default router;
