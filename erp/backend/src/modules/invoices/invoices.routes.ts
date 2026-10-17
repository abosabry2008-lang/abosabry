import { InvoiceStatus, Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, getPaging, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asDate, asEnum, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import { createInvoice, invoiceInclude, issueInvoice, updateInvoice, voidInvoice } from './invoices.service';

const router = Router();
router.use(authenticate);

const statuses: InvoiceStatus[] = ['DRAFT', 'ISSUED', 'PARTIALLY_PAID', 'PAID', 'VOID'];

const lineSchema = z.object({
  productId: z.string().nullable().optional(),
  description: z.string().optional(),
  quantity: z.number().int().positive(),
  unitPrice: z.number().min(0),
  discount: z.number().min(0).optional(),
  taxRate: z.number().min(0).max(100).optional(),
});

const createSchema = z
  .object({
    salesOrderId: z.string().nullable().optional(),
    customerId: z.string().nullable().optional(),
    currencyId: z.string().nullable().optional(),
    dueDate: z.coerce.date().nullable().optional(),
    notes: z.string().nullable().optional(),
    lines: z.array(lineSchema).min(1).optional(),
  })
  .refine((value) => Boolean(value.salesOrderId) || (value.lines && value.lines.length > 0), {
    message: 'Provide either salesOrderId or at least one line',
    path: ['lines'],
  });

const updateSchema = z
  .object({
    customerId: z.string().nullable().optional(),
    currencyId: z.string().nullable().optional(),
    dueDate: z.coerce.date().nullable().optional(),
    notes: z.string().nullable().optional(),
    lines: z.array(lineSchema).min(1).optional(),
  });

interface InvoiceMoney {
  subtotal: unknown;
  discountTotal: unknown;
  taxTotal: unknown;
  total: unknown;
  amountPaid: unknown;
  balance: unknown;
  exchangeRate: unknown;
}

const serializeInvoice = <T extends InvoiceMoney>(invoice: T) => ({
  ...invoice,
  subtotal: Number(invoice.subtotal),
  discountTotal: Number(invoice.discountTotal),
  taxTotal: Number(invoice.taxTotal),
  total: Number(invoice.total),
  amountPaid: Number(invoice.amountPaid),
  balance: Number(invoice.balance),
  exchangeRate: Number(invoice.exchangeRate),
});

router.get(
  '/',
  requirePermission('invoices.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 25);
    const customerId = asString(query.customerId);
    const status = asEnum<InvoiceStatus>(query.status as string, statuses);
    const search = asString(query.search);
    const from = asDate(query.from);
    const to = asDate(query.to);
    const unpaidOnly = asString(query.unpaid) === 'true';

    const where: Prisma.InvoiceWhereInput = {};
    if (customerId) where.customerId = customerId;
    if (status) where.status = status;
    if (unpaidOnly) where.status = { in: ['ISSUED', 'PARTIALLY_PAID'] };
    if (search) {
      where.OR = [
        { number: { contains: search, mode: 'insensitive' } },
        { customer: { name: { contains: search, mode: 'insensitive' } } },
      ];
    }
    if (from || to) {
      where.issueDate = { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) };
    }

    const [total, invoices] = await Promise.all([
      prisma.invoice.count({ where }),
      prisma.invoice.findMany({
        where,
        orderBy: { issueDate: 'desc' },
        skip: paging.skip,
        take: paging.take,
        include: {
          customer: { select: { id: true, name: true } },
          currency: { select: { id: true, code: true, symbol: true } },
          _count: { select: { lines: true, payments: true } },
        },
      }),
    ]);

    paginated(res, invoices.map((invoice) => serializeInvoice(invoice)), total, paging);
  }),
);

router.get(
  '/:id',
  requirePermission('invoices.read'),
  asyncHandler(async (req, res) => {
    const invoice = await prisma.invoice.findUnique({
      where: { id: req.params.id },
      include: invoiceInclude,
    });
    if (!invoice) throw ApiError.notFound('Invoice not found');
    ok(res, serializeInvoice(invoice));
  }),
);

router.post(
  '/',
  requirePermission('invoices.write'),
  validateBody(createSchema),
  asyncHandler(async (req, res) => {
    const invoice = await createInvoice({ ...req.body, userId: currentUser(req).id });
    created(res, serializeInvoice(invoice));
  }),
);

router.post(
  '/:id/issue',
  requirePermission('invoices.write'),
  asyncHandler(async (req, res) => {
    const invoice = await issueInvoice(req.params.id, currentUser(req).id);
    ok(res, serializeInvoice(invoice));
  }),
);

router.patch(
  '/:id',
  requirePermission('invoices.write'),
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    const invoice = await updateInvoice(req.params.id, req.body);
    ok(res, serializeInvoice(invoice));
  }),
);

router.post(
  '/:id/void',
  requirePermission('invoices.write'),
  asyncHandler(async (req, res) => {
    const invoice = await voidInvoice(req.params.id, currentUser(req).id);
    ok(res, serializeInvoice(invoice));
  }),
);

export default router;
