import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, noContent, ok } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asString } from '../../lib/query';
import { authenticate } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';

const warehouseSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  address: z.string().nullable().optional(),
  phone: z.string().nullable().optional(),
  active: z.boolean().default(true),
});

const locationSchema = z.object({
  code: z.string().min(1),
  name: z.string().nullable().optional(),
  active: z.boolean().default(true),
});

// ---------------------------------------------------------------------------
// /warehouses
// ---------------------------------------------------------------------------

export const warehousesRouter = Router();
warehousesRouter.use(authenticate);

warehousesRouter.get(
  '/',
  requirePermission('warehouses.read'),
  asyncHandler(async (_req, res) => {
    const warehouses = await prisma.warehouse.findMany({
      orderBy: { name: 'asc' },
      include: { _count: { select: { locations: true } } },
    });
    ok(res, warehouses);
  }),
);

warehousesRouter.get(
  '/:id',
  requirePermission('warehouses.read'),
  asyncHandler(async (req, res) => {
    const warehouse = await prisma.warehouse.findUnique({
      where: { id: req.params.id },
      include: { locations: { orderBy: { code: 'asc' } } },
    });
    if (!warehouse) throw ApiError.notFound('Warehouse not found');
    ok(res, warehouse);
  }),
);

warehousesRouter.post(
  '/',
  requirePermission('warehouses.write'),
  validateBody(warehouseSchema),
  asyncHandler(async (req, res) => {
    const warehouse = await prisma.warehouse.create({ data: req.body });
    created(res, warehouse);
  }),
);

warehousesRouter.patch(
  '/:id',
  requirePermission('warehouses.write'),
  validateBody(warehouseSchema.partial()),
  asyncHandler(async (req, res) => {
    const warehouse = await prisma.warehouse.update({ where: { id: req.params.id }, data: req.body });
    ok(res, warehouse);
  }),
);

warehousesRouter.delete(
  '/:id',
  requirePermission('warehouses.write'),
  asyncHandler(async (req, res) => {
    const stocked = await prisma.stockLevel.count({
      where: { warehouseId: req.params.id, quantity: { not: 0 } },
    });
    if (stocked > 0) {
      throw ApiError.conflict('Cannot delete a warehouse that still holds stock');
    }
    await prisma.warehouse.delete({ where: { id: req.params.id } });
    noContent(res);
  }),
);

warehousesRouter.get(
  '/:id/locations',
  requirePermission('warehouses.read'),
  asyncHandler(async (req, res) => {
    const locations = await prisma.location.findMany({
      where: { warehouseId: req.params.id },
      orderBy: { code: 'asc' },
      include: { _count: { select: { stockLevels: true } } },
    });
    ok(res, locations);
  }),
);

warehousesRouter.post(
  '/:id/locations',
  requirePermission('warehouses.write'),
  validateBody(locationSchema),
  asyncHandler(async (req, res) => {
    const warehouse = await prisma.warehouse.findUnique({ where: { id: req.params.id } });
    if (!warehouse) throw ApiError.notFound('Warehouse not found');
    const location = await prisma.location.create({
      data: { ...req.body, warehouseId: warehouse.id },
    });
    created(res, location);
  }),
);

// ---------------------------------------------------------------------------
// /locations
// ---------------------------------------------------------------------------

export const locationsRouter = Router();
locationsRouter.use(authenticate);

locationsRouter.get(
  '/',
  requirePermission('warehouses.read'),
  asyncHandler(async (req, res) => {
    const warehouseId = asString(req.query.warehouseId);
    const locations = await prisma.location.findMany({
      where: warehouseId ? { warehouseId } : {},
      orderBy: [{ warehouseId: 'asc' }, { code: 'asc' }],
      include: {
        warehouse: { select: { id: true, code: true, name: true } },
        _count: { select: { stockLevels: true } },
      },
    });
    ok(res, locations);
  }),
);

locationsRouter.patch(
  '/:id',
  requirePermission('warehouses.write'),
  validateBody(locationSchema.partial()),
  asyncHandler(async (req, res) => {
    const location = await prisma.location.update({ where: { id: req.params.id }, data: req.body });
    ok(res, location);
  }),
);

locationsRouter.delete(
  '/:id',
  requirePermission('warehouses.write'),
  asyncHandler(async (req, res) => {
    const rows = await prisma.stockLevel.count({ where: { locationId: req.params.id, quantity: { not: 0 } } });
    if (rows > 0) {
      throw ApiError.conflict('Cannot delete a location that still holds stock');
    }
    await prisma.location.delete({ where: { id: req.params.id } });
    noContent(res);
  }),
);
