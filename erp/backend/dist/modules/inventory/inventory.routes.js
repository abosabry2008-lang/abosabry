"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const http_1 = require("../../lib/http");
const prisma_1 = require("../../lib/prisma");
const query_1 = require("../../lib/query");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const inventory_service_1 = require("./inventory.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const movementTypes = [
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
const receiveSchema = zod_1.z.object({
    productId: zod_1.z.string().min(1),
    locationId: zod_1.z.string().min(1),
    quantity: zod_1.z.number().int().positive(),
    unitCost: zod_1.z.number().min(0).optional(),
    reference: zod_1.z.string().optional(),
    note: zod_1.z.string().optional(),
});
const dispatchSchema = receiveSchema.extend({
    allowNegative: zod_1.z.boolean().optional(),
});
const adjustSchema = zod_1.z.object({
    productId: zod_1.z.string().min(1),
    locationId: zod_1.z.string().min(1),
    quantity: zod_1.z.number().int().refine((n) => n !== 0, 'Adjustment must not be zero'),
    reason: zod_1.z.string().optional(),
});
const transferSchema = zod_1.z.object({
    productId: zod_1.z.string().min(1),
    fromLocationId: zod_1.z.string().min(1),
    toLocationId: zod_1.z.string().min(1),
    quantity: zod_1.z.number().int().positive(),
    note: zod_1.z.string().optional(),
});
const cycleCountSchema = zod_1.z.object({
    locationId: zod_1.z.string().min(1),
    note: zod_1.z.string().optional(),
    items: zod_1.z
        .array(zod_1.z.object({
        productId: zod_1.z.string().min(1),
        countedQty: zod_1.z.number().int().min(0),
    }))
        .min(1),
});
// GET /inventory/stock
router.get('/stock', (0, authorize_1.requirePermission)('inventory.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 50);
    const warehouseId = (0, query_1.asString)(query.warehouseId);
    const locationId = (0, query_1.asString)(query.locationId);
    const productId = (0, query_1.asString)(query.productId);
    const search = (0, query_1.asString)(query.search);
    const where = {};
    if (warehouseId)
        where.warehouseId = warehouseId;
    if (locationId)
        where.locationId = locationId;
    if (productId)
        where.productId = productId;
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
        prisma_1.prisma.stockLevel.count({ where }),
        prisma_1.prisma.stockLevel.findMany({
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
    (0, http_1.paginated)(res, data, total, paging);
}));
// GET /inventory/low-stock
router.get('/low-stock', (0, authorize_1.requirePermission)('inventory.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const rows = await (0, inventory_service_1.lowStockProducts)((0, query_1.asString)(req.query.warehouseId));
    (0, http_1.ok)(res, rows.map((row) => ({
        ...row.product,
        costPrice: Number(row.product.costPrice),
        salePrice: Number(row.product.salePrice),
        taxRate: Number(row.product.taxRate),
        quantity: row.quantity,
        shortage: row.shortage,
    })));
}));
// GET /inventory/movements
router.get('/movements', (0, authorize_1.requirePermission)('inventory.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 50);
    const where = {};
    const productId = (0, query_1.asString)(query.productId);
    const warehouseId = (0, query_1.asString)(query.warehouseId);
    const locationId = (0, query_1.asString)(query.locationId);
    if (productId)
        where.productId = productId;
    if (warehouseId)
        where.warehouseId = warehouseId;
    if (locationId)
        where.locationId = locationId;
    const type = (0, query_1.asEnum)(query.type, movementTypes);
    if (type)
        where.type = type;
    const from = (0, query_1.asDate)(query.from);
    const to = (0, query_1.asDate)(query.to);
    if (from || to) {
        where.createdAt = {
            ...(from ? { gte: from } : {}),
            ...(to ? { lte: to } : {}),
        };
    }
    const [total, movements] = await Promise.all([
        prisma_1.prisma.stockMovement.count({ where }),
        prisma_1.prisma.stockMovement.findMany({
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
    (0, http_1.paginated)(res, movements.map((movement) => ({ ...movement, unitCost: Number(movement.unitCost) })), total, paging);
}));
router.post('/receive', (0, authorize_1.requirePermission)('inventory.write'), (0, validate_1.validateBody)(receiveSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const result = await (0, inventory_service_1.receiveStock)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, result);
}));
router.post('/dispatch', (0, authorize_1.requirePermission)('inventory.write'), (0, validate_1.validateBody)(dispatchSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const result = await (0, inventory_service_1.dispatchStock)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, result);
}));
router.post('/adjust', (0, authorize_1.requirePermission)('inventory.write'), (0, validate_1.validateBody)(adjustSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const result = await (0, inventory_service_1.adjustStock)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, result);
}));
router.post('/transfer', (0, authorize_1.requirePermission)('inventory.write'), (0, validate_1.validateBody)(transferSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const result = await (0, inventory_service_1.transferStock)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, result);
}));
router.post('/cycle-count', (0, authorize_1.requirePermission)('inventory.write'), (0, validate_1.validateBody)(cycleCountSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const results = await (0, inventory_service_1.cycleCount)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, { results });
}));
// DELETE /inventory/stock/:productId
// Removes a product from inventory entirely: the stock levels are deleted and,
// when the product record still exists, it is soft-deleted and deactivated too.
// Works even for rows whose product was already deleted, so leftover stock can
// always be cleaned up.
router.delete('/stock/:productId', (0, authorize_1.requirePermission)('inventory.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const productId = req.params.productId;
    const removed = await prisma_1.prisma.$transaction(async (tx) => {
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
    (0, http_1.ok)(res, { productId, stockLevelsRemoved: removed });
}));
exports.default = router;
//# sourceMappingURL=inventory.routes.js.map