"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.locationsRouter = exports.warehousesRouter = void 0;
const express_1 = require("express");
const zod_1 = require("zod");
const api_error_1 = require("../../lib/api-error");
const http_1 = require("../../lib/http");
const prisma_1 = require("../../lib/prisma");
const query_1 = require("../../lib/query");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const warehouseSchema = zod_1.z.object({
    code: zod_1.z.string().min(1),
    name: zod_1.z.string().min(1),
    address: zod_1.z.string().nullable().optional(),
    phone: zod_1.z.string().nullable().optional(),
    active: zod_1.z.boolean().default(true),
});
const locationSchema = zod_1.z.object({
    code: zod_1.z.string().min(1),
    name: zod_1.z.string().nullable().optional(),
    active: zod_1.z.boolean().default(true),
});
// ---------------------------------------------------------------------------
// /warehouses
// ---------------------------------------------------------------------------
exports.warehousesRouter = (0, express_1.Router)();
exports.warehousesRouter.use(authenticate_1.authenticate);
exports.warehousesRouter.get('/', (0, authorize_1.requirePermission)('warehouses.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    const warehouses = await prisma_1.prisma.warehouse.findMany({
        orderBy: { name: 'asc' },
        include: { _count: { select: { locations: true } } },
    });
    (0, http_1.ok)(res, warehouses);
}));
exports.warehousesRouter.get('/:id', (0, authorize_1.requirePermission)('warehouses.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouse = await prisma_1.prisma.warehouse.findUnique({
        where: { id: req.params.id },
        include: { locations: { orderBy: { code: 'asc' } } },
    });
    if (!warehouse)
        throw api_error_1.ApiError.notFound('Warehouse not found');
    (0, http_1.ok)(res, warehouse);
}));
exports.warehousesRouter.post('/', (0, authorize_1.requirePermission)('warehouses.write'), (0, validate_1.validateBody)(warehouseSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouse = await prisma_1.prisma.warehouse.create({ data: req.body });
    (0, http_1.created)(res, warehouse);
}));
exports.warehousesRouter.patch('/:id', (0, authorize_1.requirePermission)('warehouses.write'), (0, validate_1.validateBody)(warehouseSchema.partial()), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouse = await prisma_1.prisma.warehouse.update({ where: { id: req.params.id }, data: req.body });
    (0, http_1.ok)(res, warehouse);
}));
exports.warehousesRouter.delete('/:id', (0, authorize_1.requirePermission)('warehouses.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const stocked = await prisma_1.prisma.stockLevel.count({
        where: { warehouseId: req.params.id, quantity: { not: 0 } },
    });
    if (stocked > 0) {
        throw api_error_1.ApiError.conflict('Cannot delete a warehouse that still holds stock');
    }
    await prisma_1.prisma.warehouse.delete({ where: { id: req.params.id } });
    (0, http_1.noContent)(res);
}));
exports.warehousesRouter.get('/:id/locations', (0, authorize_1.requirePermission)('warehouses.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const locations = await prisma_1.prisma.location.findMany({
        where: { warehouseId: req.params.id },
        orderBy: { code: 'asc' },
        include: { _count: { select: { stockLevels: true } } },
    });
    (0, http_1.ok)(res, locations);
}));
exports.warehousesRouter.post('/:id/locations', (0, authorize_1.requirePermission)('warehouses.write'), (0, validate_1.validateBody)(locationSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouse = await prisma_1.prisma.warehouse.findUnique({ where: { id: req.params.id } });
    if (!warehouse)
        throw api_error_1.ApiError.notFound('Warehouse not found');
    const location = await prisma_1.prisma.location.create({
        data: { ...req.body, warehouseId: warehouse.id },
    });
    (0, http_1.created)(res, location);
}));
// ---------------------------------------------------------------------------
// /locations
// ---------------------------------------------------------------------------
exports.locationsRouter = (0, express_1.Router)();
exports.locationsRouter.use(authenticate_1.authenticate);
exports.locationsRouter.get('/', (0, authorize_1.requirePermission)('warehouses.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouseId = (0, query_1.asString)(req.query.warehouseId);
    const locations = await prisma_1.prisma.location.findMany({
        where: warehouseId ? { warehouseId } : {},
        orderBy: [{ warehouseId: 'asc' }, { code: 'asc' }],
        include: {
            warehouse: { select: { id: true, code: true, name: true } },
            _count: { select: { stockLevels: true } },
        },
    });
    (0, http_1.ok)(res, locations);
}));
exports.locationsRouter.patch('/:id', (0, authorize_1.requirePermission)('warehouses.write'), (0, validate_1.validateBody)(locationSchema.partial()), (0, http_1.asyncHandler)(async (req, res) => {
    const location = await prisma_1.prisma.location.update({ where: { id: req.params.id }, data: req.body });
    (0, http_1.ok)(res, location);
}));
exports.locationsRouter.delete('/:id', (0, authorize_1.requirePermission)('warehouses.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const rows = await prisma_1.prisma.stockLevel.count({ where: { locationId: req.params.id, quantity: { not: 0 } } });
    if (rows > 0) {
        throw api_error_1.ApiError.conflict('Cannot delete a location that still holds stock');
    }
    await prisma_1.prisma.location.delete({ where: { id: req.params.id } });
    (0, http_1.noContent)(res);
}));
//# sourceMappingURL=warehouses.routes.js.map