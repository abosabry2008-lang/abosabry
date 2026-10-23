"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const api_error_1 = require("../../lib/api-error");
const http_1 = require("../../lib/http");
const prisma_1 = require("../../lib/prisma");
const query_1 = require("../../lib/query");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const inventory_service_1 = require("../inventory/inventory.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const productSchema = zod_1.z.object({
    sku: zod_1.z.string().min(1),
    barcode: zod_1.z.string().nullable().optional(),
    name: zod_1.z.string().min(1),
    description: zod_1.z.string().nullable().optional(),
    categoryId: zod_1.z.string().nullable().optional(),
    currencyId: zod_1.z.string().nullable().optional(),
    unit: zod_1.z.string().min(1).default('pc'),
    costPrice: zod_1.z.number().min(0).default(0),
    salePrice: zod_1.z.number().min(0).default(0),
    boxesPerCarton: zod_1.z.number().int().min(0).default(0),
    boxPrice: zod_1.z.number().min(0).nullable().optional(),
    cartonPrice: zod_1.z.number().min(0).nullable().optional(),
    taxRate: zod_1.z.number().min(0).max(100).default(0),
    reorderLevel: zod_1.z.number().int().min(0).default(0),
    trackInventory: zod_1.z.boolean().default(true),
    active: zod_1.z.boolean().default(true),
    imageUrl: zod_1.z.string().nullable().optional(),
});
const updateSchema = productSchema.partial();
const include = {
    category: { select: { id: true, name: true } },
    currency: { select: { id: true, code: true, symbol: true } },
};
function serializeProduct(product, stockQuantity) {
    return {
        ...product,
        costPrice: Number(product.costPrice),
        salePrice: Number(product.salePrice),
        taxRate: Number(product.taxRate),
        stockQuantity,
    };
}
function buildWhere(query, includeInactive) {
    const search = (0, query_1.asString)(query.search);
    const categoryId = (0, query_1.asString)(query.categoryId);
    const includeDeleted = (0, query_1.asBool)(query.includeDeleted) === true;
    const where = {};
    // Products that were deleted disappear from the catalogue unless asked for.
    if (!includeDeleted)
        where.deletedAt = null;
    if (!includeInactive)
        where.active = true;
    if (categoryId)
        where.categoryId = categoryId;
    if (search) {
        where.OR = [
            { name: { contains: search, mode: 'insensitive' } },
            { sku: { contains: search, mode: 'insensitive' } },
            { barcode: { contains: search, mode: 'insensitive' } },
        ];
    }
    return where;
}
router.get('/', (0, authorize_1.requirePermission)('products.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query);
    const includeInactive = (0, query_1.asBool)(query.includeInactive) === true;
    const lowStock = (0, query_1.asBool)(query.lowStock) === true;
    const search = (0, query_1.asString)(query.search);
    const categoryId = (0, query_1.asString)(query.categoryId);
    if (lowStock) {
        const rows = await (0, inventory_service_1.lowStockProducts)((0, query_1.asString)(query.warehouseId));
        const filtered = rows.filter((row) => {
            if (categoryId && row.product.categoryId !== categoryId)
                return false;
            if (search) {
                const haystack = `${row.product.name} ${row.product.sku} ${row.product.barcode ?? ''}`.toLowerCase();
                if (!haystack.includes(search.toLowerCase()))
                    return false;
            }
            return true;
        });
        const slice = filtered.slice(paging.skip, paging.skip + paging.take);
        (0, http_1.paginated)(res, slice.map((row) => serializeProduct(row.product, row.quantity)), filtered.length, paging);
        return;
    }
    const where = buildWhere(query, includeInactive);
    const [total, products] = await Promise.all([
        prisma_1.prisma.product.count({ where }),
        prisma_1.prisma.product.findMany({
            where,
            include,
            orderBy: { name: 'asc' },
            skip: paging.skip,
            take: paging.take,
        }),
    ]);
    const stock = await (0, inventory_service_1.totalStockByProduct)(products.map((product) => product.id));
    (0, http_1.paginated)(res, products.map((product) => serializeProduct(product, stock.get(product.id) ?? 0)), total, paging);
}));
router.get('/barcode/:code', (0, authorize_1.requirePermission)('products.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const product = await prisma_1.prisma.product.findFirst({
        where: { barcode: req.params.code, deletedAt: null },
        include,
    });
    if (!product)
        throw api_error_1.ApiError.notFound('No product matches that barcode');
    const stock = await (0, inventory_service_1.totalStockByProduct)([product.id]);
    (0, http_1.ok)(res, serializeProduct(product, stock.get(product.id) ?? 0));
}));
router.get('/:id', (0, authorize_1.requirePermission)('products.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const product = await prisma_1.prisma.product.findFirst({
        where: { id: req.params.id, deletedAt: null },
        include,
    });
    if (!product)
        throw api_error_1.ApiError.notFound('Product not found');
    const stock = await (0, inventory_service_1.totalStockByProduct)([product.id]);
    (0, http_1.ok)(res, serializeProduct(product, stock.get(product.id) ?? 0));
}));
router.post('/', (0, authorize_1.requirePermission)('products.write'), (0, validate_1.validateBody)(productSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const product = await prisma_1.prisma.product.create({ data: req.body, include });
    (0, http_1.created)(res, serializeProduct(product, 0));
}));
router.patch('/:id', (0, authorize_1.requirePermission)('products.write'), (0, validate_1.validateBody)(updateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const existing = await prisma_1.prisma.product.findFirst({ where: { id: req.params.id } });
    if (!existing)
        throw api_error_1.ApiError.notFound('Product not found');
    const product = await prisma_1.prisma.product.update({
        where: { id: existing.id },
        data: { ...req.body, deletedAt: null },
        include,
    });
    const stock = await (0, inventory_service_1.totalStockByProduct)([product.id]);
    (0, http_1.ok)(res, serializeProduct(product, stock.get(product.id) ?? 0));
}));
// Restores a soft-deleted product back into the catalogue.
router.post('/:id/restore', (0, authorize_1.requirePermission)('products.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const existing = await prisma_1.prisma.product.findFirst({ where: { id: req.params.id } });
    if (!existing)
        throw api_error_1.ApiError.notFound('Product not found');
    const product = await prisma_1.prisma.product.update({
        where: { id: existing.id },
        data: { deletedAt: null, active: true },
        include,
    });
    const stock = await (0, inventory_service_1.totalStockByProduct)([product.id]);
    (0, http_1.ok)(res, serializeProduct(product, stock.get(product.id) ?? 0));
}));
router.delete('/:id', (0, authorize_1.requirePermission)('products.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const existing = await prisma_1.prisma.product.findFirst({ where: { id: req.params.id, deletedAt: null } });
    if (!existing)
        throw api_error_1.ApiError.notFound('Product not found');
    // Soft delete keeps historical orders and movements intact.
    await prisma_1.prisma.product.update({
        where: { id: existing.id },
        data: { deletedAt: new Date(), active: false },
    });
    (0, http_1.noContent)(res);
}));
exports.default = router;
//# sourceMappingURL=products.routes.js.map