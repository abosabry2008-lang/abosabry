import { Prisma, ReturnType, ReturnOrderStatus } from '@prisma/client';
import { Router, type RequestHandler } from 'express';
import { z } from 'zod';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, getPaging, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asEnum, asString } from '../../lib/query';
import { roleHasPermission, type Permission } from '../../lib/permissions';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { validateBody } from '../../middleware/validate';
import {
  cancelReturnOrder,
  createReturnOrder,
  postReturnOrder,
  returnOrderInclude,
  updateReturnOrder,
} from './returns.service';

const router = Router();
router.use(authenticate);

/** مرتجعات العملاء تندرج تحت صلاحيات المبيعات، ومرتجعات الموردين تحت المشتريات. */
function requireAnyPermission(permissions: Permission[]): RequestHandler {
  return (req, _res, next) => {
    if (!req.user) throw ApiError.unauthorized();
    if (!permissions.some((permission) => roleHasPermission(req.user!.role, permission))) {
      throw ApiError.forbidden(`Your role (${req.user.role}) lacks the required permission`);
    }
    next();
  };
}

const readPermission = requireAnyPermission(['sales.read', 'purchasing.read']);
const writePermission = requireAnyPermission(['sales.write', 'purchasing.write']);

const lineSchema = z.object({
  productId: z.string().min(1),
  quantity: z.number().int().positive(),
  unitPrice: z.number().min(0).optional(),
  taxRate: z.number().min(0).max(100).optional(),
});

const createSchema = z.object({
  type: z.nativeEnum(ReturnType),
  customerId: z.string().nullable().optional(),
  supplierId: z.string().nullable().optional(),
  warehouseId: z.string().min(1),
  notes: z.string().nullable().optional(),
  lines: z.array(lineSchema).min(1),
});

const updateSchema = z.object({
  notes: z.string().nullable().optional(),
  lines: z.array(lineSchema).min(1).optional(),
});

const statuses: ReturnOrderStatus[] = ['DRAFT', 'POSTED', 'CANCELLED'];

const serialize = <T extends { subtotal: unknown; taxTotal: unknown; total: unknown }>(order: T) => ({
  ...order,
  subtotal: Number(order.subtotal),
  taxTotal: Number(order.taxTotal),
  total: Number(order.total),
});

router.get(
  '/',
  readPermission,
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 25);
    const type = asEnum<ReturnType>(query.type as string, ['CUSTOMER_RETURN', 'SUPPLIER_RETURN']);
    const status = asEnum<ReturnOrderStatus>(query.status as string, statuses);
    const search = asString(query.search);

    const where: Prisma.ReturnOrderWhereInput = {};
    if (type) where.type = type;
    if (status) where.status = status;
    if (search) {
      where.OR = [
        { number: { contains: search, mode: 'insensitive' } },
        { customer: { name: { contains: search, mode: 'insensitive' } } },
        { supplier: { name: { contains: search, mode: 'insensitive' } } },
      ];
    }

    const [total, orders] = await Promise.all([
      prisma.returnOrder.count({ where }),
      prisma.returnOrder.findMany({
        where,
        orderBy: { returnDate: 'desc' },
        skip: paging.skip,
        take: paging.take,
        include: {
          customer: { select: { id: true, name: true } },
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
  '/:id',
  readPermission,
  asyncHandler(async (req, res) => {
    const order = await prisma.returnOrder.findUnique({
      where: { id: req.params.id },
      include: returnOrderInclude,
    });
    if (!order) throw ApiError.notFound('Return order not found');
    ok(res, serialize(order));
  }),
);

router.post(
  '/',
  writePermission,
  validateBody(createSchema),
  asyncHandler(async (req, res) => {
    const order = await createReturnOrder({ ...req.body, userId: currentUser(req).id });
    created(res, serialize(order));
  }),
);

router.patch(
  '/:id',
  writePermission,
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    const order = await updateReturnOrder(req.params.id, req.body, {
      allowPosted: roleHasPermission(user.role, 'returns.edit'),
    });
    ok(res, serialize(order));
  }),
);

router.post(
  '/:id/post',
  writePermission,
  asyncHandler(async (req, res) => {
    const order = await postReturnOrder(req.params.id, currentUser(req).id);
    ok(res, serialize(order));
  }),
);

router.post(
  '/:id/cancel',
  writePermission,
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    const order = await cancelReturnOrder(req.params.id, {
      allowPosted: roleHasPermission(user.role, 'returns.cancel'),
    });
    ok(res, serialize(order));
  }),
);

export default router;
