"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const client_1 = require("@prisma/client");
const express_1 = require("express");
const zod_1 = require("zod");
const http_1 = require("../../lib/http");
const query_1 = require("../../lib/query");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const settlements_service_1 = require("./settlements.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const settlementSchema = zod_1.z.object({
    target: zod_1.z.nativeEnum(client_1.SettlementTarget),
    direction: zod_1.z.nativeEnum(client_1.SettlementDirection).optional(),
    customerId: zod_1.z.string().nullable().optional(),
    supplierId: zod_1.z.string().nullable().optional(),
    categoryId: zod_1.z.string().nullable().optional(),
    amount: zod_1.z.number().refine((value) => value !== 0, { message: 'Amount cannot be zero' }),
    reference: zod_1.z.string().nullable().optional(),
    note: zod_1.z.string().nullable().optional(),
    settledAt: zod_1.z.coerce.date().nullable().optional(),
});
const updateSchema = zod_1.z.object({
    direction: zod_1.z.nativeEnum(client_1.SettlementDirection).optional(),
    amount: zod_1.z.number().optional(),
    reference: zod_1.z.string().nullable().optional(),
    note: zod_1.z.string().nullable().optional(),
    settledAt: zod_1.z.coerce.date().nullable().optional(),
});
const serialize = (settlement) => ({
    ...settlement,
    amount: Number(settlement.amount),
});
router.get('/', (0, authorize_1.requirePermission)('treasury.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 25);
    const target = (0, query_1.asString)(query.target);
    const result = await (0, settlements_service_1.listSettlements)({
        target: target && Object.values(client_1.SettlementTarget).includes(target) ? target : undefined,
        customerId: (0, query_1.asString)(query.customerId),
        supplierId: (0, query_1.asString)(query.supplierId),
        categoryId: (0, query_1.asString)(query.categoryId),
        from: (0, query_1.asDate)(query.from),
        to: (0, query_1.asDate)(query.to),
        includeCancelled: (0, query_1.asBool)(query.includeCancelled) === true,
        search: (0, query_1.asString)(query.search),
        skip: paging.skip,
        take: paging.take,
    });
    res.status(200).json({
        data: result.items.map(serialize),
        meta: {
            page: paging.page,
            pageSize: paging.pageSize,
            total: result.total,
            totalPages: paging.take > 0 ? Math.ceil(result.total / paging.take) : 0,
        },
    });
}));
router.get('/:id', (0, authorize_1.requirePermission)('treasury.read'), (0, http_1.asyncHandler)(async (req, res) => {
    (0, http_1.ok)(res, serialize(await (0, settlements_service_1.getSettlement)(req.params.id)));
}));
router.post('/', (0, authorize_1.requirePermission)('treasury.write'), (0, validate_1.validateBody)(settlementSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const settlement = await (0, settlements_service_1.createSettlement)({
        ...req.body,
        userId: (0, authenticate_1.currentUser)(req).id,
    });
    (0, http_1.created)(res, serialize(settlement));
}));
router.patch('/:id', (0, authorize_1.requirePermission)('treasury.write'), (0, validate_1.validateBody)(updateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    (0, http_1.ok)(res, serialize(await (0, settlements_service_1.updateSettlement)(req.params.id, {
        ...req.body,
        userId: (0, authenticate_1.currentUser)(req).id,
    })));
}));
router.delete('/:id', (0, authorize_1.requirePermission)('treasury.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    (0, http_1.ok)(res, serialize(await (0, settlements_service_1.cancelSettlement)(req.params.id, (0, authenticate_1.currentUser)(req).id)));
}));
exports.default = router;
//# sourceMappingURL=settlements.routes.js.map