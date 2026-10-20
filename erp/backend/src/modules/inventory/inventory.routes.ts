import { MovementType, Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, created, getPaging, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asDate, asEnum, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import {
  adjustStock,
  cycleCount,
  dispatchStock,
  lowStockProducts,
  receiveStock,
  transferStock,
} from './inventory.service';

const router = Router();
router.use(authenticate);

const movementTypes: MovementType[] = [
  'OPENING',
  'RECEIVE',
  'DISPATCH',
  'ADJUSTMENT',
  'TRANSFER_IN',
  'TRANSFER_OUT',
  'SALE',
  'SALE_RETURN',
  'PURCHASE',
  'PURCHASE_RETURN',
  'CYCLE_COUNT',
];

const receiveSchema = z.object({
  productId: z.string().min(1),
  locationId: z.string().min(1),
  quantity: z.number().int().positive(),
  unitCost: z.number().min(0).optional(),
  reference: z.string().optional(),
  note: z.string().optional(),
});

const dispatchSchema = receiveSchema.extend({
  allowNegative: z.boolean().optional(),
});

const adjustSchema = z.object({
  productId: z.string().min(1),
  locationId: z.string().min(1),
  quantity: z.number().int().refine((n) => n !== 0, 'Adjustment must not be zero'),
  reason: z.string().optional(),
});

const transferSchema = z.object({
  productId: z.string().min(1),
  fromLocationId: z.string().min(1),
  toLocationId: z.string().min(1),
  quantity: z.number().int().positive(),
  note: z.string().optional(),
});

const cycleCountSchema = z.object({
  locationId: z.string().min(1),
  note: z.string().optional(),
  items: z
    .array(
      z.object({
        productId: z.string().min(1),
        countedQty: z.number().int().min(0),
      }),
    )
    .min(1),
});

// GET /inventory/stock
router.get(
  '/stock',
  requirePermission('inventory.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 50);
    const warehouseId = asString(query.warehouseId);
    const locationId = asString(query.locationId);
    const productId = asString(query.productId);
    const search = asString(query.search);

    const where: Prisma.StockLevelWhereInput = {};
    if (warehouseId) where.warehouseId = warehouseId;
    if (locationId) where.locationId = locationId;
    if (productId) where.productId = productId;
    if (search) {
      where.product = {
        OR: [
          { name: { contains: search, mode: 'insensitive' } },
          { sku: { contains: search, mode: 'insensitive' } },
          { barcode: { contains: search, mode: 'insensitive' } },
        ],
      };
    }

    const [total, rows] = await Promise.all([
      prisma.stockLevel.count({ where }),
      prisma.stockLevel.findMany({
        where,
        orderBy: [{ productId: 'asc' }, { locationId: 'asc' }],
        skip: paging.skip,
        take: paging.take,
        include: {
          product: {
            select: {
              id: true,
              sku: true,
              barcode: true,
              name: true,
              unit: true,
              reorderLevel: true,
              costPrice: true,
              salePrice: true,
            },
          },
          location: { select: { id: true, code: true, name: true } },
          warehouse: { select: { id: true, code: true, name: true } },
        },
      }),
    ]);

    const data = rows.map((row) => ({
      ...row,
      available: row.quantity - row.reserved,
      isLow: row.product.reorderLevel > 0 && row.quantity <= row.product.reorderLevel,
      product: {
        ...row.product,
        costPrice: Number(row.product.costPrice),
        salePrice: Number(row.product.salePrice),
      },
    }));

    paginated(res, data, total, paging);
  }),
);

// GET /inventory/low-stock
router.get(
  '/low-stock',
  requirePermission('inventory.read'),
  asyncHandler(async (req, res) => {
    const rows = await lowStockProducts(asString(req.query.warehouseId));
    ok(
      res,
      rows.map((row) => ({
        ...row.product,
        costPrice: Number(row.product.costPrice),
        salePrice: Number(row.product.salePrice),
        taxRate: Number(row.product.taxRate),
        quantity: row.quantity,
        shortage: row.shortage,
      })),
    );
  }),
);

// GET /inventory/movements
router.get(
  '/movements',
  requirePermission('inventory.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 50);

    const where: Prisma.StockMovementWhereInput = {};
    const productId = asString(query.productId);
    const warehouseId = asString(query.warehouseId);
    const locationId = asString(query.locationId);
    if (productId) where.productId = productId;
    if (warehouseId) where.warehouseId = warehouseId;
    if (locationId) where.locationId = locationId;
    const type = asEnum<MovementType>(query.type as string, movementTypes);
    if (type) where.type = type;
    const from = asDate(query.from);
    const to = asDate(query.to);
    if (from || to) {
      where.createdAt = {
        ...(from ? { gte: from } : {}),
        ...(to ? { lte: to } : {}),
      };
    }

    const [total, movements] = await Promise.all([
      prisma.stockMovement.count({ where }),
      prisma.stockMovement.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: paging.skip,
        take: paging.take,
        include: {
          product: { select: { id: true, sku: true, name: true, unit: true } },
          location: { select: { id: true, code: true, name: true } },
          user: { select: { id: true, name: true } },
        },
      }),
    ]);

    paginated(
      res,
      movements.map((movement) => ({ ...movement, unitCost: Number(movement.unitCost) })),
      total,
      paging,
    );
  }),
);

router.post(
  '/receive',
  requirePermission('inventory.write'),
  validateBody(receiveSchema),
  asyncHandler(async (req, res) => {
    const result = await receiveStock({ ...req.body, userId: currentUser(req).id });
    created(res, result);
  }),
);

router.post(
  '/dispatch',
  requirePermission('inventory.write'),
  validateBody(dispatchSchema),
  asyncHandler(async (req, res) => {
    const result = await dispatchStock({ ...req.body, userId: currentUser(req).id });
    created(res, result);
  }),
);

router.post(
  '/adjust',
  requirePermission('inventory.write'),
  validateBody(adjustSchema),
  asyncHandler(async (req, res) => {
    const result = await adjustStock({ ...req.body, userId: currentUser(req).id });
    created(res, result);
  }),
);

router.post(
  '/transfer',
  requirePermission('inventory.write'),
  validateBody(transferSchema),
  asyncHandler(async (req, res) => {
    const result = await transferStock({ ...req.body, userId: currentUser(req).id });
    created(res, result);
  }),
);

router.post(
  '/cycle-count',
  requirePermission('inventory.write'),
  validateBody(cycleCountSchema),
  asyncHandler(async (req, res) => {
    const results = await cycleCount({ ...req.body, userId: currentUser(req).id });
    created(res, { results });
  }),
);

// DELETE /inventory/stock/:productId
// Removes a product from inventory entirely: the stock levels are deleted and,
// when the product record still exists, it is soft-deleted and deactivated too.
// Works even for rows whose product was already deleted, so leftover stock can
// always be cleaned up.
router.delete(
  '/stock/:productId',
  requirePermission('inventory.write'),
  asyncHandler(async (req, res) => {
    const productId = req.params.productId;
    const removed = await prisma.$transaction(async (tx) => {
      const deleted = await tx.stockLevel.deleteMany({ where: { productId } });
      const product = await tx.product.findUnique({ where: { id: productId } });
      if (product) {
        await tx.product.update({
          where: { id: productId },
          data: { deletedAt: product.deletedAt ?? new Date(), active: false },
        });
      }
      return deleted.count;
    });
    ok(res, { productId, stockLevelsRemoved: removed });
  }),
);

export default router;
