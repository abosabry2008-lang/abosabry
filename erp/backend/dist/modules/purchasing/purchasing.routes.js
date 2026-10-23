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
const permissions_1 = require("../../lib/permissions");
const purchasing_service_1 = require("./purchasing.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const statuses = [
    'DRAFT',
    'PENDING',
    'APPROVED',
    'PARTIALLY_RECEIVED',
    'RECEIVED',
    'CANCELLED',
];
const lineSchema = zod_1.z.object({
    productId: zod_1.z.string().min(1),
    quantity: zod_1.z.number().int().positive(),
    unitCost: zod_1.z.number().min(0),
    taxRate: zod_1.z.number().min(0).max(100).optional(),
});
const createSchema = zod_1.z.object({
    supplierId: zod_1.z.string().min(1),
    warehouseId: zod_1.z.string().min(1),
    currencyId: zod_1.z.string().nullable().optional(),
    expectedDate: zod_1.z.coerce.date().nullable().optional(),
    notes: zod_1.z.string().nullable().optional(),
    lines: zod_1.z.array(lineSchema).min(1),
});
const updateSchema = zod_1.z.object({
    currencyId: zod_1.z.string().nullable().optional(),
    expectedDate: zod_1.z.coerce.date().nullable().optional(),
    notes: zod_1.z.string().nullable().optional(),
    lines: zod_1.z.array(lineSchema).min(1).optional(),
});
const receiveSchema = zod_1.z.object({
    lines: zod_1.z
        .array(zod_1.z.object({ lineId: zod_1.z.string().min(1), quantity: zod_1.z.number().int().positive() }))
        .optional(),
});
const serialize = (order) => ({
    ...order,
    subtotal: Number(order.subtotal),
    taxTotal: Number(order.taxTotal),
    total: Number(order.total),
});
router.get('/', (0, authorize_1.requirePermission)('purchasing.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 25);
    const supplierId = (0, query_1.asString)(query.supplierId);
    const status = (0, query_1.asEnum)(query.status, statuses);
    const search = (0, query_1.asString)(query.search);
    const where = {};
    if (supplierId)
        where.supplierId = supplierId;
    if (status)
        where.status = status;
    if (search) {
        where.OR = [
            { number: { contains: search, mode: 'insensitive' } },
            { supplier: { name: { contains: search, mode: 'insensitive' } } },
        ];
    }
    const [total, orders] = await Promise.all([
        prisma_1.prisma.purchaseOrder.count({ where }),
        prisma_1.prisma.purchaseOrder.findMany({
            where,
            orderBy: { orderDate: 'desc' },
            skip: paging.skip,
            take: paging.take,
            include: {
                supplier: { select: { id: true, name: true } },
                warehouse: { select: { id: true, code: true, name: true } },
                _count: { select: { lines: true } },
            },
        }),
    ]);
    (0, http_1.paginated)(res, orders.map((order) => serialize(order)), total, paging);
}));
router.get('/:id', (0, authorize_1.requirePermission)('purchasing.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const order = await prisma_1.prisma.purchaseOrder.findUnique({
        where: { id: req.params.id },
        include: purchasing_service_1.purchaseOrderInclude,
    });
    if (!order)
        throw api_error_1.ApiError.notFound('Purchase order not found');
    (0, http_1.ok)(res, serialize(order));
}));
router.post('/', (0, authorize_1.requirePermission)('purchasing.write'), (0, validate_1.validateBody)(createSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const order = await (0, purchasing_service_1.createPurchaseOrder)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, serialize(order));
}));
router.patch('/:id', (0, authorize_1.requirePermission)('purchasing.write'), (0, validate_1.validateBody)(updateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const user = (0, authenticate_1.currentUser)(req);
    const order = await (0, purchasing_service_1.updatePurchaseOrder)(req.params.id, req.body, {
        allowPosted: (0, permissions_1.roleHasPermission)(user.role, 'purchases.cancel'),
        userId: user.id,
    });
    (0, http_1.ok)(res, serialize(order));
}));
router.post('/:id/approve', (0, authorize_1.requirePermission)('purchasing.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const order = await (0, purchasing_service_1.setPurchaseOrderStatus)(req.params.id, 'APPROVED');
    (0, http_1.ok)(res, serialize(order));
}));
router.post('/:id/receive', (0, authorize_1.requirePermission)('purchasing.write'), (0, validate_1.validateBody)(receiveSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const order = await (0, purchasing_service_1.receivePurchaseOrder)(req.params.id, {
        lines: req.body.lines,
        userId: (0, authenticate_1.currentUser)(req).id,
    });
    (0, http_1.ok)(res, serialize(order));
}));
router.post('/:id/cancel', (0, authorize_1.requirePermission)('purchases.cancel'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const order = await (0, purchasing_service_1.setPurchaseOrderStatus)(req.params.id, 'CANCELLED', {
        userId: (0, authenticate_1.currentUser)(req).id,
    });
    (0, http_1.ok)(res, serialize(order));
}));
exports.default = router;
//# sourceMappingURL=purchasing.routes.js.map