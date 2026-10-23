"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const client_1 = require("@prisma/client");
const express_1 = require("express");
const zod_1 = require("zod");
const api_error_1 = require("../../lib/api-error");
const http_1 = require("../../lib/http");
const prisma_1 = require("../../lib/prisma");
const query_1 = require("../../lib/query");
const permissions_1 = require("../../lib/permissions");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const returns_service_1 = require("./returns.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
/** مرتجعات العملاء تندرج تحت صلاحيات المبيعات، ومرتجعات الموردين تحت المشتريات. */
function requireAnyPermission(permissions) {
    return (req, _res, next) => {
        if (!req.user)
            throw api_error_1.ApiError.unauthorized();
        if (!permissions.some((permission) => (0, permissions_1.roleHasPermission)(req.user.role, permission))) {
            throw api_error_1.ApiError.forbidden(`Your role (${req.user.role}) lacks the required permission`);
        }
        next();
    };
}
const readPermission = requireAnyPermission(['sales.read', 'purchasing.read']);
const writePermission = requireAnyPermission(['sales.write', 'purchasing.write']);
const lineSchema = zod_1.z.object({
    productId: zod_1.z.string().min(1),
    quantity: zod_1.z.number().int().positive(),
    unitPrice: zod_1.z.number().min(0).optional(),
    taxRate: zod_1.z.number().min(0).max(100).optional(),
});
const createSchema = zod_1.z.object({
    type: zod_1.z.nativeEnum(client_1.ReturnType),
    customerId: zod_1.z.string().nullable().optional(),
    supplierId: zod_1.z.string().nullable().optional(),
    warehouseId: zod_1.z.string().min(1),
    notes: zod_1.z.string().nullable().optional(),
    lines: zod_1.z.array(lineSchema).min(1),
});
const updateSchema = zod_1.z.object({
    notes: zod_1.z.string().nullable().optional(),
    lines: zod_1.z.array(lineSchema).min(1).optional(),
});
const statuses = ['DRAFT', 'POSTED', 'CANCELLED'];
const serialize = (order) => ({
    ...order,
    subtotal: Number(order.subtotal),
    taxTotal: Number(order.taxTotal),
    total: Number(order.total),
});
router.get('/', readPermission, (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 25);
    const type = (0, query_1.asEnum)(query.type, ['CUSTOMER_RETURN', 'SUPPLIER_RETURN']);
    const status = (0, query_1.asEnum)(query.status, statuses);
    const search = (0, query_1.asString)(query.search);
    const where = {};
    if (type)
        where.type = type;
    if (status)
        where.status = status;
    if (search) {
        where.OR = [
            { number: { contains: search, mode: 'insensitive' } },
            { customer: { name: { contains: search, mode: 'insensitive' } } },
            { supplier: { name: { contains: search, mode: 'insensitive' } } },
        ];
    }
    const [total, orders] = await Promise.all([
        prisma_1.prisma.returnOrder.count({ where }),
        prisma_1.prisma.returnOrder.findMany({
            where,
            orderBy: { returnDate: 'desc' },
            skip: paging.skip,
            take: paging.take,
            include: {
                customer: { select: { id: true, name: true } },
                supplier: { select: { id: true, name: true } },
                warehouse: { select: { id: true, code: true, name: true } },
                _count: { select: { lines: true } },
            },
        }),
    ]);
    (0, http_1.paginated)(res, orders.map((order) => serialize(order)), total, paging);
}));
router.get('/:id', readPermission, (0, http_1.asyncHandler)(async (req, res) => {
    const order = await prisma_1.prisma.returnOrder.findUnique({
        where: { id: req.params.id },
        include: returns_service_1.returnOrderInclude,
    });
    if (!order)
        throw api_error_1.ApiError.notFound('Return order not found');
    (0, http_1.ok)(res, serialize(order));
}));
router.post('/', writePermission, (0, validate_1.validateBody)(createSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const order = await (0, returns_service_1.createReturnOrder)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, serialize(order));
}));
router.patch('/:id', writePermission, (0, validate_1.validateBody)(updateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const user = (0, authenticate_1.currentUser)(req);
    const order = await (0, returns_service_1.updateReturnOrder)(req.params.id, req.body, {
        allowPosted: (0, permissions_1.roleHasPermission)(user.role, 'returns.edit'),
    });
    (0, http_1.ok)(res, serialize(order));
}));
router.post('/:id/post', writePermission, (0, http_1.asyncHandler)(async (req, res) => {
    const order = await (0, returns_service_1.postReturnOrder)(req.params.id, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.ok)(res, serialize(order));
}));
router.post('/:id/cancel', writePermission, (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const user = (0, authenticate_1.currentUser)(req);
    const order = await (0, returns_service_1.cancelReturnOrder)(req.params.id, {
        allowPosted: (0, permissions_1.roleHasPermission)(user.role, 'returns.cancel'),
    });
    (0, http_1.ok)(res, serialize(order));
}));
exports.default = router;
//# sourceMappingURL=returns.routes.js.map