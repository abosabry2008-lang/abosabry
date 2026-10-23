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
    code: zod_1.z.string().min(1).max(8),
    name: zod_1.z.string().min(1),
    symbol: zod_1.z.string().min(1).default('$'),
    exchangeRate: zod_1.z.number().positive().default(1),
    isBase: zod_1.z.boolean().default(false),
    active: zod_1.z.boolean().default(true),
});
const updateSchema = zod_1.z.object({
    code: zod_1.z.string().min(1).max(8).optional(),
    name: zod_1.z.string().min(1).optional(),
    symbol: zod_1.z.string().min(1).optional(),
    exchangeRate: zod_1.z.number().positive().optional(),
    isBase: zod_1.z.boolean().optional(),
    active: zod_1.z.boolean().optional(),
});
router.get('/', (0, authorize_1.requirePermission)('currency.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    const currencies = await prisma_1.prisma.currency.findMany({ orderBy: [{ isBase: 'desc' }, { code: 'asc' }] });
    (0, http_1.ok)(res, currencies);
}));
router.post('/', (0, authorize_1.requirePermission)('currency.write'), (0, validate_1.validateBody)(createSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const { isBase, ...rest } = req.body;
    const currency = await prisma_1.prisma.$transaction(async (tx) => {
        if (isBase) {
            await tx.currency.updateMany({ data: { isBase: false } });
        }
        return tx.currency.create({
            data: { ...rest, isBase: Boolean(isBase), exchangeRate: isBase ? 1 : rest.exchangeRate },
        });
    });
    (0, http_1.created)(res, currency);
}));
router.patch('/:id', (0, authorize_1.requirePermission)('currency.write'), (0, validate_1.validateBody)(updateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const { isBase, ...rest } = req.body;
    const currency = await prisma_1.prisma.$transaction(async (tx) => {
        if (isBase) {
            await tx.currency.updateMany({ data: { isBase: false } });
        }
        return tx.currency.update({
            where: { id: req.params.id },
            data: { ...rest, ...(isBase === undefined ? {} : { isBase }), ...(isBase ? { exchangeRate: 1 } : {}) },
        });
    });
    (0, http_1.ok)(res, currency);
}));
router.delete('/:id', (0, authorize_1.requirePermission)('currency.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const currency = await prisma_1.prisma.currency.findUnique({ where: { id: req.params.id } });
    if (!currency)
        throw api_error_1.ApiError.notFound('Currency not found');
    if (currency.isBase)
        throw api_error_1.ApiError.badRequest('The base currency cannot be deleted');
    await prisma_1.prisma.currency.delete({ where: { id: req.params.id } });
    (0, http_1.noContent)(res);
}));
exports.default = router;
//# sourceMappingURL=currency.routes.js.map