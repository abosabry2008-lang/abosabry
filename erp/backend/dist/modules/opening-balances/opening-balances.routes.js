"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const http_1 = require("../../lib/http");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const opening_balances_service_1 = require("./opening-balances.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const createSchema = zod_1.z.object({
    asOfDate: zod_1.z.coerce.date().optional(),
    note: zod_1.z.string().max(500).nullable().optional(),
    customers: zod_1.z
        .array(zod_1.z.object({
        customerId: zod_1.z.string().min(1),
        amount: zod_1.z.number().nonnegative(),
    }))
        .optional(),
    suppliers: zod_1.z
        .array(zod_1.z.object({
        supplierId: zod_1.z.string().min(1),
        amount: zod_1.z.number().nonnegative(),
    }))
        .optional(),
    inventory: zod_1.z
        .array(zod_1.z.object({
        warehouseId: zod_1.z.string().min(1),
        productId: zod_1.z.string().min(1),
        quantity: zod_1.z.number().int().positive(),
        unitCost: zod_1.z.number().nonnegative(),
    }))
        .optional(),
});
router.get('/', (0, authorize_1.requirePermission)('openingBalances.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    (0, http_1.ok)(res, await (0, opening_balances_service_1.listOpeningBalances)());
}));
router.post('/', (0, authorize_1.requirePermission)('openingBalances.write'), (0, validate_1.validateBody)(createSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const entry = await (0, opening_balances_service_1.createOpeningBalance)({
        ...req.body,
        userId: (0, authenticate_1.currentUser)(req).id,
    });
    (0, http_1.created)(res, entry);
}));
router.post('/:id/cancel', (0, authorize_1.requirePermission)('openingBalances.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const entry = await (0, opening_balances_service_1.cancelOpeningBalance)(req.params.id, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.ok)(res, entry);
}));
exports.default = router;
//# sourceMappingURL=opening-balances.routes.js.map