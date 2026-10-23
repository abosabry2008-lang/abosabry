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
const sales_service_1 = require("./sales.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const statuses = [
    'DRAFT',
    'CONFIRMED',
    'PARTIALLY_FULFILLED',
    'FULFILLED',
    'CANCELLED',
];
const lineSchema = zod_1.z.object({
    productId: zod_1.z.string().min(1),
    quantity: zod_1.z.number().int().positive(),
    unitPrice: zod_1.z.number().min(0).optional(),
    discount: zod_1.z.number().min(0).optional(),
    taxRate: zod_1.z.number().min(0).max(100).optional(),
    /** When selling in packs: "unit" (default), "box", or "carton". */
    sellUnit: zod_1.z.enum(['unit', 'box', 'carton']).optional(),
});
const createSchema = zod_1.z.object({
    customerId: zod_1.z.string().nullable().optional(),
    warehouseId: zod_1.z.string().min(1),
    currencyId: zod_1.z.string().nullable().optional(),
    notes: zod_1.z.string().nullable().optional(),
    lines: zod_1.z.array(lineSchema).min(1),
});
const updateSchema = zod_1.z.object({
    customerId: zod_1.z.string().nullable().optional(),
    currencyId: zod_1.z.string().nullable().optional(),
    notes: zod_1.z.string().nullable().optional(),
    lines: zod_1.z.array(lineSchema).min(1).optional(),
});
const fulfillSchema = zod_1.z.object({
    lines: zod_1.z
        .array(zod_1.z.object({ lineId: zod_1.z.string().min(1), quantity: zod_1.z.number().int().positive() }))
        .optional(),
    onlyAvailable: zod_1.z.boolean().optional(),
});
const serialize = (order) => ({
    ...order,
    subtotal: Number(order.subtotal),
    discountTotal: Number(order.discountTotal),
    taxTotal: Number(order.taxTotal),
    total: Number(order.total),
});
router.get('/', (0, authorize_1.requirePermission)('sales.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 25);
    const customerId = (0, query_1.asString)(query.customerId);
    const warehouseId = (0, query_1.asString)(query.warehouseId);
    const status = (0, query_1.asEnum)(query.status, statuses);
    const channel = (0, query_1.asString)(query.channel);
    const search = (0, query_1.asString)(query.search);
    const from = (0, query_1.asDate)(query.from);
    const to = (0, query_1.asDate)(query.to);
    const where = {};
    if (customerId)
        where.customerId = customerId;
    if (warehouseId)
        where.warehouseId = warehouseId;
    if (status)
        where.status = status;
    if (channel)
        where.channel = channel;
    if (search) {
        where.OR = [
            { number: { contains: search, mode: 'insensitive' } },
            { customer: { name: { contains: search, mode: 'insensitive' } } },
        ];
    }
    if (from || to) {
        where.orderDate = { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) };
    }
    const [total, orders] = await Promise.all([
        prisma_1.prisma.salesOrder.count({ where }),
        prisma_1.prisma.salesOrder.findMany({
            where,
            orderBy: { orderDate: 'desc' },
            skip: paging.skip,
            take: paging.take,
            include: {
                customer: { select: { id: true, name: true } },
                warehouse: { select: { id: true, code: true, name: true } },
                _count: { select: { lines: true, invoices: true } },
            },
        }),
    ]);
    (0, http_1.paginated)(res, orders.map((order) => serialize(order)), total, paging);
}));
router.get('/:id', (0, authorize_1.requirePermission)('sales.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const order = await prisma_1.prisma.salesOrder.findUnique({
        where: { id: req.params.id },
        include: { ...sales_service_1.salesOrderInclude, invoices: { select: { id: true, number: true, status: true, total: true, balance: true } } },
    });
    if (!order)
        throw api_error_1.ApiError.notFound('Sales order not found');
    (0, http_1.ok)(res, serialize(order));
}));
router.post('/', (0, authorize_1.requirePermission)('sales.write'), (0, validate_1.validateBody)(createSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const order = await (0, sales_service_1.createSalesOrder)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, serialize(order));
}));
router.patch('/:id', (0, authorize_1.requirePermission)('sales.write'), (0, validate_1.validateBody)(updateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const user = (0, authenticate_1.currentUser)(req);
    const order = await (0, sales_service_1.updateSalesOrder)(req.params.id, req.body, {
        allowPosted: (0, permissions_1.roleHasPermission)(user.role, 'sales.cancel'),
        userId: user.id,
    });
    (0, http_1.ok)(res, serialize(order));
}));
router.get('/:id/availability', (0, authorize_1.requirePermission)('sales.read'), (0, http_1.asyncHandler)(async (req, res) => {
    (0, http_1.ok)(res, await (0, sales_service_1.checkSalesOrderAvailability)(req.params.id));
}));
router.post('/:id/confirm', (0, authorize_1.requirePermission)('sales.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const order = await (0, sales_service_1.confirmSalesOrder)(req.params.id);
    (0, http_1.ok)(res, serialize(order));
}));
router.post('/:id/fulfill', (0, authorize_1.requirePermission)('sales.write'), (0, validate_1.validateBody)(fulfillSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const order = await (0, sales_service_1.fulfillSalesOrder)(req.params.id, {
        lines: req.body.lines,
        onlyAvailable: req.body.onlyAvailable,
        userId: (0, authenticate_1.currentUser)(req).id,
    });
    (0, http_1.ok)(res, serialize(order));
}));
router.post('/:id/cancel', (0, authorize_1.requirePermission)('sales.cancel'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const order = await (0, sales_service_1.cancelSalesOrder)(req.params.id, { userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.ok)(res, serialize(order));
}));
exports.default = router;
//# sourceMappingURL=sales.routes.js.map