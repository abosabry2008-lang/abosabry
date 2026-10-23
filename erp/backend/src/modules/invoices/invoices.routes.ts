import { InvoiceStatus, Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, getPaging, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { round2 } from '../../lib/money';
import { asDate, asEnum, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission, requireAdmin } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import { roleHasPermission } from '../../lib/permissions';
import {
  assertCustomerAccess,
  assertInvoiceAccess,
  assertSalesOrderAccess,
  invoiceAccessWhere,
  scopedSalespersonId,
} from '../../lib/salesperson-scope';
import {
  backfillCostSnapshots,
  createInvoice,
  invoiceInclude,
  issueInvoice,
  previewInvoiceFromOrder,
  updateInvoice,
  voidInvoice,
} from './invoices.service';

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
    skipUnavailable: z.boolean().optional(),
    issue: z.boolean().optional(),
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
    const user = currentUser(req);
    const salespersonId = scopedSalespersonId(
      user,
      asString(query.salespersonId),
    );
    const access = invoiceAccessWhere(user);

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
    if (access) {
      where.AND = [...(Array.isArray(where.AND) ? where.AND : where.AND ? [where.AND] : []), access];
    }
    if (salespersonId) {
      where.AND = [
        ...(Array.isArray(where.AND) ? where.AND : where.AND ? [where.AND] : []),
        {
          OR: [
            { customer: { salespersonId } },
            { customerId: null, salesOrder: { userId: salespersonId } },
          ],
        },
      ];
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
  '/preview-from-order/:orderId',
  requirePermission('invoices.read'),
  asyncHandler(async (req, res) => {
    await assertSalesOrderAccess(currentUser(req), req.params.orderId);
    ok(res, await previewInvoiceFromOrder(req.params.orderId));
  }),
);

// Stores cost snapshots on older invoice/order lines (admin repair, idempotent).
router.post(
  '/backfill-costs',
  requireAdmin(),
  asyncHandler(async (_req, res) => {
    ok(res, await backfillCostSnapshots());
  }),
);

// Last price this customer was invoiced for a product (sales-invoice hint).
router.get(
  '/last-price',
  requirePermission('invoices.read'),
  asyncHandler(async (req, res) => {
    const customerId = asString(req.query.customerId);
    const productId = asString(req.query.productId);
    if (!customerId || !productId) {
      throw ApiError.badRequest('customerId and productId are required');
    }
    await assertCustomerAccess(currentUser(req), customerId);
    const line = await prisma.invoiceLine.findFirst({
      where: {
        productId,
        invoice: { customerId, status: { in: ['ISSUED', 'PARTIALLY_PAID', 'PAID'] } },
      },
      orderBy: { invoice: { issueDate: 'desc' } },
      select: {
        unitPrice: true,
        sellUnit: true,
        invoice: { select: { number: true, issueDate: true } },
      },
    });
    ok(
      res,
      line
        ? {
            unitPrice: Number(line.unitPrice),
            sellUnit: line.sellUnit,
            invoiceNumber: line.invoice.number,
            issueDate: line.invoice.issueDate,
          }
        : null,
    );
  }),
);

router.get(
  '/:id',
  requirePermission('invoices.read'),
  asyncHandler(async (req, res) => {
    await assertInvoiceAccess(currentUser(req), req.params.id);
    const invoice = await prisma.invoice.findUnique({
      where: { id: req.params.id },
      include: invoiceInclude,
    });
    if (!invoice) throw ApiError.notFound('Invoice not found');

    // What the customer owed before this invoice. The stored customer balance
    // only counts ISSUED/PARTIALLY_PAID/PAID invoices, so a draft contributes
    // nothing and the whole balance is "previous"; for an issued invoice its own
    // outstanding balance is subtracted.
    const counted = ['ISSUED', 'PARTIALLY_PAID', 'PAID'].includes(invoice.status);
    const previousBalance = invoice.customer
      ? round2(Number(invoice.customer.balance) - (counted ? Number(invoice.balance) : 0))
      : 0;

    ok(res, { ...serializeInvoice(invoice), previousBalance });
  }),
);

router.post(
  '/',
  requirePermission('invoices.write'),
  validateBody(createSchema),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    await assertCustomerAccess(user, req.body.customerId);
    if (req.body.salesOrderId) await assertSalesOrderAccess(user, req.body.salesOrderId);
    const invoice = await createInvoice({ ...req.body, userId: user.id });
    created(res, serializeInvoice(invoice));
  }),
);

router.post(
  '/:id/issue',
  requirePermission('invoices.write'),
  asyncHandler(async (req, res) => {
    await assertInvoiceAccess(currentUser(req), req.params.id);
    const invoice = await issueInvoice(req.params.id, currentUser(req).id);
    ok(res, serializeInvoice(invoice));
  }),
);

router.patch(
  '/:id',
  requirePermission('invoices.write'),
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    await assertInvoiceAccess(user, req.params.id);
    await assertCustomerAccess(user, req.body.customerId);
    // Draft invoices may be edited by whoever is entering them; once issued only
    // an administrator may change them.
    const existing = await prisma.invoice.findUnique({
      where: { id: req.params.id },
      select: { status: true },
    });
    if (
      existing &&
      existing.status !== 'DRAFT' &&
      (user.role ?? '').toUpperCase() !== 'ADMIN'
    ) {
      throw ApiError.forbidden('Only an administrator can edit an issued invoice');
    }
    const invoice = await updateInvoice(req.params.id, req.body, {
      allowPosted: roleHasPermission(user.role, 'invoices.edit'),
      userId: user.id,
    });
    ok(res, serializeInvoice(invoice));
  }),
);

router.post(
  '/:id/void',
  requirePermission('invoices.cancel'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const invoice = await voidInvoice(req.params.id, currentUser(req).id);
    ok(res, serializeInvoice(invoice));
  }),
);

export default router;
