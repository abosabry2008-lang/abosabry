import { Prisma, PurchaseOrderStatus } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, getPaging, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asEnum, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission, requireAdmin } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import { roleHasPermission } from '../../lib/permissions';
import {
  createPurchaseOrder,
  purchaseOrderInclude,
  receivePurchaseOrder,
  setPurchaseOrderStatus,
  updatePurchaseOrder,
} from './purchasing.service';

const router = Router();
router.use(authenticate);

const statuses: PurchaseOrderStatus[] = [
  'DRAFT',
  'PENDING',
  'APPROVED',
  'PARTIALLY_RECEIVED',
  'RECEIVED',
  'CANCELLED',
];

const lineSchema = z.object({
  productId: z.string().min(1),
  quantity: z.number().int().positive(),
  unitCost: z.number().min(0),
  taxRate: z.number().min(0).max(100).optional(),
  sellUnit: z.enum(['unit', 'box', 'carton']).optional(),
});

const createSchema = z.object({
  supplierId: z.string().min(1),
  warehouseId: z.string().min(1),
  currencyId: z.string().nullable().optional(),
  expectedDate: z.coerce.date().nullable().optional(),
  notes: z.string().nullable().optional(),
  lines: z.array(lineSchema).min(1),
});

const updateSchema = z.object({
  currencyId: z.string().nullable().optional(),
  expectedDate: z.coerce.date().nullable().optional(),
  notes: z.string().nullable().optional(),
  lines: z.array(lineSchema).min(1).optional(),
});

const receiveSchema = z.object({
  lines: z
    .array(z.object({ lineId: z.string().min(1), quantity: z.number().int().positive() }))
    .optional(),
});

const serialize = <T extends { subtotal: unknown; taxTotal: unknown; total: unknown }>(order: T) => ({
  ...order,
  subtotal: Number(order.subtotal),
  taxTotal: Number(order.taxTotal),
  total: Number(order.total),
});

router.get(
  '/',
  requirePermission('purchasing.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 25);
    const supplierId = asString(query.supplierId);
    const status = asEnum<PurchaseOrderStatus>(query.status as string, statuses);
    const search = asString(query.search);

    const where: Prisma.PurchaseOrderWhereInput = {};
    if (supplierId) where.supplierId = supplierId;
    if (status) where.status = status;
    if (search) {
      where.OR = [
        { number: { contains: search, mode: 'insensitive' } },
        { supplier: { name: { contains: search, mode: 'insensitive' } } },
      ];
    }

    const [total, orders] = await Promise.all([
      prisma.purchaseOrder.count({ where }),
      prisma.purchaseOrder.findMany({
        where,
        orderBy: { orderDate: 'desc' },
        skip: paging.skip,
        take: paging.take,
        include: {
          supplier: { select: { id: true, name: true } },
          warehouse: { select: { id: true, code: true, name: true } },
          _count: { select: { lines: true } },
        },
      }),
    ]);

    paginated(res, orders.map((order) => serialize(order)), total, paging);
  }),
);

router.get(
  '/last-price',
  requirePermission('purchasing.read'),
  asyncHandler(async (req, res) => {
    const supplierId = asString(req.query.supplierId);
    const productId = asString(req.query.productId);
    if (!supplierId || !productId) {
      throw ApiError.badRequest('supplierId and productId are required');
    }
    const line = await prisma.purchaseOrderLine.findFirst({
      where: {
        productId,
        purchaseOrder: {
          supplierId,
          status: { in: ['PARTIALLY_RECEIVED', 'RECEIVED'] },
        },
      },
      orderBy: { purchaseOrder: { orderDate: 'desc' } },
      select: {
        unitCost: true,
        purchaseOrder: { select: { number: true, orderDate: true } },
      },
    });
    ok(
      res,
      line
        ? {
            unitPrice: Number(line.unitCost),
            orderNumber: line.purchaseOrder.number,
            orderDate: line.purchaseOrder.orderDate,
          }
        : null,
    );
  }),
);

router.get(
  '/:id',
  requirePermission('purchasing.read'),
  asyncHandler(async (req, res) => {
    const order = await prisma.purchaseOrder.findUnique({
      where: { id: req.params.id },
      include: purchaseOrderInclude,
    });
    if (!order) throw ApiError.notFound('Purchase order not found');
    ok(res, serialize(order));
  }),
);

router.post(
  '/',
  requirePermission('purchasing.write'),
  validateBody(createSchema),
  asyncHandler(async (req, res) => {
    const order = await createPurchaseOrder({ ...req.body, userId: currentUser(req).id });
    created(res, serialize(order));
  }),
);

router.patch(
  '/:id',
  requirePermission('purchasing.write'),
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    const order = await updatePurchaseOrder(req.params.id, req.body, {
      allowPosted: roleHasPermission(user.role, 'purchases.cancel'),
      userId: user.id,
    });
    ok(res, serialize(order));
  }),
);

router.post(
  '/:id/approve',
  requirePermission('purchasing.write'),
  asyncHandler(async (req, res) => {
    const order = await setPurchaseOrderStatus(req.params.id, 'APPROVED');
    ok(res, serialize(order));
  }),
);

router.post(
  '/:id/receive',
  requirePermission('purchasing.write'),
  validateBody(receiveSchema),
  asyncHandler(async (req, res) => {
    const order = await receivePurchaseOrder(req.params.id, {
      lines: req.body.lines,
      userId: currentUser(req).id,
    });
    ok(res, serialize(order));
  }),
);

router.post(
  '/:id/cancel',
  requirePermission('purchases.cancel'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const order = await setPurchaseOrderStatus(req.params.id, 'CANCELLED', {
      userId: currentUser(req).id,
    });
    ok(res, serialize(order));
  }),
);

export default router;
