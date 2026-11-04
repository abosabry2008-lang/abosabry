import { MovementType, Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, created, getPaging, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asDate, asDateEnd, asEnum, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission, requireAdmin } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import {
  adjustStock,
  cycleCount,
  dispatchStock,
  lowStockProducts,
  receiveStock,
  transferStock,
  transferStockBatch,
  warehouseAvailability,
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
  note: z.string().nullish(),
});

const batchTransferSchema = z.object({
  fromWarehouseId: z.string().min(1),
  toWarehouseId: z.string().min(1),
  note: z.string().nullish(),
  items: z
    .array(
      z.object({
        productId: z.string().min(1),
        quantity: z.number().int().positive(),
        sellUnit: z.enum(['unit', 'box', 'carton']).optional(),
      }),
    )
    .min(1),
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
    const categoryId = asString(query.categoryId);
    const search = asString(query.search);
    const lowStock = asString(query.lowStock) === 'true';
    const stockStatus = asString(query.stockStatus);
    const sort = asString(query.sort);

    const where: Prisma.StockLevelWhereInput = {};
    if (warehouseId) where.warehouseId = warehouseId;
    if (locationId) where.locationId = locationId;
    if (productId) where.productId = productId;

    const productWhere: Prisma.ProductWhereInput = {};
    if (categoryId) productWhere.categoryId = categoryId;
    if (search) {
      productWhere.OR = [
        { name: { contains: search, mode: 'insensitive' } },
        { sku: { contains: search, mode: 'insensitive' } },
        { barcode: { contains: search, mode: 'insensitive' } },
      ];
    }
    if (lowStock || stockStatus === 'low') productWhere.reorderLevel = { gt: 0 };
    if (Object.keys(productWhere).length > 0) where.product = productWhere;

    if (stockStatus === 'out') where.quantity = { lte: 0 };
    if (stockStatus === 'in') where.quantity = { gt: 0 };

    let orderBy: Prisma.StockLevelOrderByWithRelationInput[];
    switch (sort) {
      case 'name':
        orderBy = [{ product: { name: 'asc' } }, { locationId: 'asc' }];
        break;
      case 'name_desc':
        orderBy = [{ product: { name: 'desc' } }, { locationId: 'asc' }];
        break;
      case 'sku':
        orderBy = [{ product: { sku: 'asc' } }, { locationId: 'asc' }];
        break;
      case 'quantity':
        orderBy = [{ quantity: 'desc' }, { productId: 'asc' }];
        break;
      case 'quantity_asc':
        orderBy = [{ quantity: 'asc' }, { productId: 'asc' }];
        break;
      case 'newest':
        orderBy = [{ updatedAt: 'desc' }];
        break;
      default:
        orderBy = [{ productId: 'asc' }, { locationId: 'asc' }];
    }

    const include = {
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
    } as const;

    // "Low stock" compares two columns (quantity <= product.reorderLevel),
    // which Prisma cannot express across relations, so filter it in memory.
    const result = await (async () => {
      if (lowStock || stockStatus === 'low') {
        const all = await prisma.stockLevel.findMany({ where, orderBy, include });
        const low = all.filter(
          (row) => row.product.reorderLevel > 0 && row.quantity <= row.product.reorderLevel,
        );
        return {
          total: low.length,
          rows: low.slice(paging.skip, paging.skip + paging.take),
        };
      }
      const [total, rows] = await Promise.all([
        prisma.stockLevel.count({ where }),
        prisma.stockLevel.findMany({
          where,
          orderBy,
          skip: paging.skip,
          take: paging.take,
          include,
        }),
      ]);
      return { total, rows };
    })();
    const { total, rows } = result;

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

// GET /inventory/availability?warehouseId=
router.get(
  '/availability',
  requirePermission('inventory.read'),
  asyncHandler(async (req, res) => {
    const warehouseId = asString(req.query.warehouseId);
    if (!warehouseId) {
      res.status(400).json({
        error: { message: 'warehouseId is required', code: 'WAREHOUSE_REQUIRED' },
      });
      return;
    }
    ok(res, await warehouseAvailability(warehouseId));
  }),
);

router.post(
  '/transfer',
  requirePermission('inventory.write'),
  validateBody(transferSchema),
  asyncHandler(async (req, res) => {
    const result = await transferStock({
      ...req.body,
      note: req.body.note ?? undefined,
      userId: currentUser(req).id,
    });
    created(res, result);
  }),
);

// POST /inventory/transfers — one multi-item transfer voucher.
router.post(
  '/transfers',
  requirePermission('inventory.write'),
  validateBody(batchTransferSchema),
  asyncHandler(async (req, res) => {
    const result = await transferStockBatch({
      ...req.body,
      note: req.body.note ?? undefined,
      userId: currentUser(req).id,
    });
    created(res, result);
  }),
);

// GET /inventory/transfers?from=&to=&warehouseId=&search=
router.get(
  '/transfers',
  requirePermission('inventory.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDateEnd(req.query.to);
    const warehouseId = asString(req.query.warehouseId);
    const search = asString(req.query.search);
    const limit = Math.min(
      300,
      Math.max(1, Number(asString(req.query.limit) ?? 100)),
    );

    const baseWhere: Prisma.StockMovementWhereInput = {
      type: { in: ['TRANSFER_OUT', 'TRANSFER_IN'] },
      reference: { startsWith: 'TRF-' },
      ...(from || to
        ? {
            createdAt: {
              ...(from ? { gte: from } : {}),
              ...(to ? { lte: to } : {}),
            },
          }
        : {}),
      ...(warehouseId ? { warehouseId } : {}),
      ...(search
        ? {
            OR: [
              { reference: { contains: search, mode: 'insensitive' } },
              { product: { name: { contains: search, mode: 'insensitive' } } },
              { product: { sku: { contains: search, mode: 'insensitive' } } },
            ],
          }
        : {}),
    };

    const matched = await prisma.stockMovement.findMany({
      where: baseWhere,
      select: { reference: true, createdAt: true },
      orderBy: { createdAt: 'desc' },
      take: limit * 6,
    });
    const references = [
      ...new Set(
        matched
          .map((row) => row.reference)
          .filter((value): value is string => Boolean(value)),
      ),
    ].slice(0, limit);

    if (references.length === 0) {
      ok(res, { rows: [], count: 0 });
      return;
    }

    const [movements, warehouses] = await Promise.all([
      prisma.stockMovement.findMany({
        where: {
          reference: { in: references },
          type: { in: ['TRANSFER_OUT', 'TRANSFER_IN'] },
        },
        orderBy: { createdAt: 'asc' },
        include: {
          product: {
            select: { id: true, name: true, sku: true, boxesPerCarton: true },
          },
        },
      }),
      prisma.warehouse.findMany({
        select: { id: true, code: true, name: true },
      }),
    ]);
    const warehouseName = new Map(
      warehouses.map((warehouse) => [warehouse.id, warehouse]),
    );

    const grouped = new Map<
      string,
      {
        number: string;
        date: Date;
        fromWarehouseId: string | null;
        toWarehouseId: string | null;
        note: string | null;
        lines: {
          productId: string;
          name: string;
          sku: string | null;
          boxes: number;
        }[];
      }
    >();

    for (const movement of movements) {
      const number = movement.reference!;
      const entry = grouped.get(number) ?? {
        number,
        date: movement.createdAt,
        fromWarehouseId: null,
        toWarehouseId: null,
        note: movement.note,
        lines: [],
      };
      if (movement.createdAt < entry.date) entry.date = movement.createdAt;
      if (movement.type === 'TRANSFER_OUT') {
        entry.fromWarehouseId = movement.warehouseId;
        entry.lines.push({
          productId: movement.product.id,
          name: movement.product.name,
          sku: movement.product.sku,
          boxes: Math.abs(movement.quantity),
        });
      } else {
        entry.toWarehouseId = movement.warehouseId;
      }
      grouped.set(number, entry);
    }

    const rows = [...grouped.values()]
      .map((entry) => ({
        number: entry.number,
        date: entry.date.toISOString(),
        fromWarehouseId: entry.fromWarehouseId,
        fromWarehouse: entry.fromWarehouseId
          ? (warehouseName.get(entry.fromWarehouseId) ?? null)
          : null,
        toWarehouseId: entry.toWarehouseId,
        toWarehouse: entry.toWarehouseId
          ? (warehouseName.get(entry.toWarehouseId) ?? null)
          : null,
        note: entry.note,
        lineCount: entry.lines.length,
        totalBoxes: entry.lines.reduce((sum, line) => sum + line.boxes, 0),
        lines: entry.lines,
      }))
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
      .slice(0, limit);

    ok(res, { rows, count: rows.length });
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
  requireAdmin(),
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
