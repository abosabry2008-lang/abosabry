"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const prisma_1 = require("../../lib/prisma");
const api_error_1 = require("../../lib/api-error");
const http_1 = require("../../lib/http");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const createSchema = zod_1.z.object({
    name: zod_1.z.string().min(1),
    description: zod_1.z.string().nullable().optional(),
});
const updateSchema = createSchema.partial();
router.get('/', (0, authorize_1.requirePermission)('categories.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    const categories = await prisma_1.prisma.category.findMany({
        orderBy: { name: 'asc' },
        include: { _count: { select: { products: true } } },
    });
    (0, http_1.ok)(res, categories);
}));
router.post('/', (0, authorize_1.requirePermission)('categories.write'), (0, validate_1.validateBody)(createSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const category = await prisma_1.prisma.category.create({ data: req.body });
    (0, http_1.created)(res, category);
}));
router.patch('/:id', (0, authorize_1.requirePermission)('categories.write'), (0, validate_1.validateBody)(updateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const category = await prisma_1.prisma.category.update({ where: { id: req.params.id }, data: req.body });
    (0, http_1.ok)(res, category);
}));
router.delete('/:id', (0, authorize_1.requirePermission)('categories.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const products = await prisma_1.prisma.product.count({ where: { categoryId: req.params.id, deletedAt: null } });
    if (products > 0) {
        throw api_error_1.ApiError.conflict(`Cannot delete: ${products} product(s) still use this category`);
    }
    await prisma_1.prisma.category.delete({ where: { id: req.params.id } });
    (0, http_1.noContent)(res);
}));
exports.default = router;
//# sourceMappingURL=categories.routes.js.map