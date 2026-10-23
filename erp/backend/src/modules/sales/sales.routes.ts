import { Prisma, SalesOrderStatus } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, getPaging, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asDate, asEnum, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission, requireAdmin } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import { roleHasPermission } from '../../lib/permissions';
import { createInvoiceTx, issueInvoiceTx } from '../invoices/invoices.service';
import {
  assertCustomerAccess,
  assertSalesOrderAccess,
  salesOrderAccessWhere,
} from '../../lib/salesperson-scope';
import {
  cancelSalesOrder,
  checkSalesOrderAvailability,
  confirmSalesOrder,
  createSalesOrder,
  fulfillSalesOrder,
  fulfillSalesOrderTx,
  salesOrderInclude,
  updateSalesOrder,
} from './sales.service';

const router = Router();
router.use(authenticate);

const statuses: SalesOrderStatus[] = [
  'DRAFT',
  'CONFIRMED',
  'PARTIALLY_FULFILLED',
  'FULFILLED',
  'CANCELLED',
];

const lineSchema = z.object({
  productId: z.string().min(1),
  quantity: z.number().int().positive(),
  unitPrice: z.number().min(0).optional(),
  discount: z.number().min(0).optional(),
  taxRate: z.number().min(0).max(100).optional(),
  /** When selling in packs: "unit" (default), "box", or "carton". */
  sellUnit: z.enum(['unit', 'box', 'carton']).optional(),
});

const createSchema = z.object({
  customerId: z.string().nullable().optional(),
  warehouseId: z.string().min(1),
  currencyId: z.string().nullable().optional(),
  notes: z.string().nullable().optional(),
  lines: z.array(lineSchema).min(1),
});

const updateSchema = z.object({
  customerId: z.string().nullable().optional(),
  currencyId: z.string().nullable().optional(),
  notes: z.string().nullable().optional(),
  lines: z.array(lineSchema).min(1).optional(),
});

const fulfillSchema = z.object({
  lines: z
    .array(z.object({ lineId: z.string().min(1), quantity: z.number().int().positive() }))
    .optional(),
  onlyAvailable: z.boolean().optional(),
});

const serialize = <T extends { subtotal: unknown; discountTotal: unknown; taxTotal: unknown; total: unknown }>(
  order: T,
) => ({
  ...order,
  subtotal: Number(order.subtotal),
  discountTotal: Number(order.discountTotal),
  taxTotal: Number(order.taxTotal),
  total: Number(order.total),
});

router.get(
  '/',
  requirePermission('sales.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 25);
    const customerId = asString(query.customerId);
    const warehouseId = asString(query.warehouseId);
    const status = asEnum<SalesOrderStatus>(query.status as string, statuses);
    const channel = asString(query.channel);
    const search = asString(query.search);
    const from = asDate(query.from);
    const to = asDate(query.to);
    const access = salesOrderAccessWhere(currentUser(req));

    const where: Prisma.SalesOrderWhereInput = {};
    if (customerId) where.customerId = customerId;
    if (warehouseId) where.warehouseId = warehouseId;
    if (status) where.status = status;
    if (channel) where.channel = channel as Prisma.SalesOrderWhereInput['channel'];
    if (search) {
      where.OR = [
        { number: { contains: search, mode: 'insensitive' } },
        { customer: { name: { contains: search, mode: 'insensitive' } } },
      ];
    }
    if (from || to) {
      where.orderDate = { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) };
    }
    if (access) {
      where.AND = [...(Array.isArray(where.AND) ? where.AND : where.AND ? [where.AND] : []), access];
    }

    const [total, orders] = await Promise.all([
      prisma.salesOrder.count({ where }),
      prisma.salesOrder.findMany({
        where,
        orderBy: { orderDate: 'desc' },
        skip: paging.skip,
        take: paging.take,
        include: {
          customer: { select: { id: true, name: true } },
          warehouse: { select: { id: true, code: true, name: true } },
          _count: { select: { lines: true, invoices: true } },
        },
      }),
    ]);

    paginated(res, orders.map((order) => serialize(order)), total, paging);
  }),
);

router.get(
  '/:id',
  requirePermission('sales.read'),
  asyncHandler(async (req, res) => {
    await assertSalesOrderAccess(currentUser(req), req.params.id);
    const order = await prisma.salesOrder.findUnique({
      where: { id: req.params.id },
      include: { ...salesOrderInclude, invoices: { select: { id: true, number: true, status: true, total: true, balance: true } } },
    });
    if (!order) throw ApiError.notFound('Sales order not found');
    ok(res, serialize(order));
  }),
);

router.post(
  '/',
  requirePermission('sales.write'),
  validateBody(createSchema),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    await assertCustomerAccess(user, req.body.customerId);
    const order = await createSalesOrder({ ...req.body, userId: user.id });
    created(res, serialize(order));
  }),
);

router.patch(
  '/:id',
  requirePermission('sales.write'),
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    await assertSalesOrderAccess(user, req.params.id);
    await assertCustomerAccess(user, req.body.customerId);
    const order = await updateSalesOrder(req.params.id, req.body, {
      allowPosted: roleHasPermission(user.role, 'sales.cancel'),
      userId: user.id,
    });
    ok(res, serialize(order));
  }),
);

router.get(
  '/:id/availability',
  requirePermission('sales.read'),
  asyncHandler(async (req, res) => {
    await assertSalesOrderAccess(currentUser(req), req.params.id);
    ok(res, await checkSalesOrderAvailability(req.params.id));
  }),
);

router.post(
  '/:id/confirm',
  requirePermission('sales.write'),
  asyncHandler(async (req, res) => {
    await assertSalesOrderAccess(currentUser(req), req.params.id);
    const order = await confirmSalesOrder(req.params.id);
    ok(res, serialize(order));
  }),
);

// One-step execution: fulfil the order and issue its invoice together.
router.post(
  '/:id/execute',
  requirePermission('sales.write'),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    await assertSalesOrderAccess(user, req.params.id);
    const result = await prisma.$transaction(async (tx) => {
      const existingInvoice = await tx.invoice.findFirst({
        where: { salesOrderId: req.params.id, status: { not: 'VOID' } },
        select: { id: true, number: true, status: true },
      });
      const current = await tx.salesOrder.findUnique({
        where: { id: req.params.id },
        select: { status: true },
      });
      if (!current) throw ApiError.notFound('Sales order not found');
      // Pressing execute again on an already fulfilled order just returns it.
      const order =
        current.status === 'FULFILLED'
          ? await tx.salesOrder.findUniqueOrThrow({
              where: { id: req.params.id },
              include: salesOrderInclude,
            })
          : await fulfillSalesOrderTx(tx, req.params.id, {
              onlyAvailable: req.body?.onlyAvailable === true,
              userId: user.id,
            });
      if (existingInvoice) return { order, invoice: existingInvoice };
      if (!order.lines.some((line) => line.fulfilledQty > 0)) {
        throw ApiError.badRequest(
          'No stock is available to execute this order',
          'NOTHING_AVAILABLE',
        );
      }
      const draft = await createInvoiceTx(tx, {
        salesOrderId: req.params.id,
        userId: user.id,
      });
      const invoice = await issueInvoiceTx(tx, draft.id, user.id);
      return {
        order,
        invoice: { id: invoice.id, number: invoice.number, status: invoice.status },
      };
    });
    ok(res, { order: serialize(result.order), invoice: result.invoice });
  }),
);

router.post(
  '/:id/fulfill',
  requirePermission('sales.write'),
  validateBody(fulfillSchema),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    await assertSalesOrderAccess(user, req.params.id);
    const order = await fulfillSalesOrder(req.params.id, {
      lines: req.body.lines,
      onlyAvailable: req.body.onlyAvailable,
      userId: user.id,
    });
    ok(res, serialize(order));
  }),
);

router.post(
  '/:id/cancel',
  requirePermission('sales.cancel'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const order = await cancelSalesOrder(req.params.id, { userId: currentUser(req).id });
    ok(res, serialize(order));
  }),
);

export default router;
