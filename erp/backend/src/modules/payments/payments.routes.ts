import { PaymentDirection, PaymentMethod, Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, created, getPaging, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asBool, asDate, asEnum, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission, requireAdmin } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import {
  cancelPayment,
  createPayment,
  paymentInclude,
  updatePayment,
} from './payments.service';

const router = Router();
router.use(authenticate);

const methods: PaymentMethod[] = ['CASH', 'CARD', 'BANK_TRANSFER', 'MOBILE_MONEY', 'CHEQUE', 'OTHER'];
const directions: PaymentDirection[] = ['INBOUND', 'OUTBOUND'];

const createSchema = z.object({
  direction: z.nativeEnum(PaymentDirection).optional(),
  invoiceId: z.string().nullable().optional(),
  customerId: z.string().nullable().optional(),
  supplierId: z.string().nullable().optional(),
  currencyId: z.string().nullable().optional(),
  cashBoxId: z.string().nullable().optional(),
  method: z.nativeEnum(PaymentMethod).optional(),
  amount: z.number().positive(),
  reference: z.string().nullable().optional(),
  note: z.string().nullable().optional(),
  paidAt: z.coerce.date().nullable().optional(),
});

const updateSchema = z.object({
  amount: z.number().positive().optional(),
  cashBoxId: z.string().nullable().optional(),
  reference: z.string().nullable().optional(),
  note: z.string().nullable().optional(),
  paidAt: z.coerce.date().nullable().optional(),
});

interface PaymentMoney {
  amount: unknown;
  invoice: { total: unknown; balance: unknown } | null;
}

const serializePayment = <T extends PaymentMoney>(payment: T) => ({
  ...payment,
  amount: Number(payment.amount),
  invoice: payment.invoice
    ? { ...payment.invoice, total: Number(payment.invoice.total), balance: Number(payment.invoice.balance) }
    : null,
});

router.get(
  '/',
  requirePermission('payments.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 25);
    const customerId = asString(query.customerId);
    const supplierId = asString(query.supplierId);
    const invoiceId = asString(query.invoiceId);
    const cashBoxId = asString(query.cashBoxId);
    const direction = asEnum<PaymentDirection>(query.direction as string, directions);
    const method = asEnum<PaymentMethod>(query.method as string, methods);
    const includeCancelled = asBool(query.includeCancelled) === true;
    const from = asDate(query.from);
    const to = asDate(query.to);

    const where: Prisma.PaymentWhereInput = {};
    if (!includeCancelled) where.cancelledAt = null;
    if (customerId) where.customerId = customerId;
    if (supplierId) where.supplierId = supplierId;
    if (invoiceId) where.invoiceId = invoiceId;
    if (cashBoxId) where.cashBoxId = cashBoxId;
    if (direction) where.direction = direction;
    if (method) where.method = method;
    if (from || to) {
      where.paidAt = { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) };
    }

    const [total, payments] = await Promise.all([
      prisma.payment.count({ where }),
      prisma.payment.findMany({
        where,
        orderBy: { paidAt: 'desc' },
        skip: paging.skip,
        take: paging.take,
        include: paymentInclude,
      }),
    ]);

    paginated(res, payments.map((payment) => serializePayment(payment)), total, paging);
  }),
);

router.post(
  '/',
  requirePermission('payments.write'),
  validateBody(createSchema),
  asyncHandler(async (req, res) => {
    const payment = await createPayment({ ...req.body, userId: currentUser(req).id });
    created(res, serializePayment(payment));
  }),
);

router.patch(
  '/:id',
  requirePermission('treasury.write'),
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    const payment = await updatePayment(req.params.id, req.body, currentUser(req).id);
    ok(res, serializePayment(payment));
  }),
);

router.post(
  '/:id/cancel',
  requirePermission('treasury.write'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const payment = await cancelPayment(req.params.id, currentUser(req).id);
    ok(res, serializePayment(payment));
  }),
);

export default router;
