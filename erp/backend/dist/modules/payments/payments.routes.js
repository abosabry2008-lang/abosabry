"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const client_1 = require("@prisma/client");
const express_1 = require("express");
const zod_1 = require("zod");
const http_1 = require("../../lib/http");
const prisma_1 = require("../../lib/prisma");
const query_1 = require("../../lib/query");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const payments_service_1 = require("./payments.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const methods = ['CASH', 'CARD', 'BANK_TRANSFER', 'MOBILE_MONEY', 'CHEQUE', 'OTHER'];
const directions = ['INBOUND', 'OUTBOUND'];
const createSchema = zod_1.z.object({
    direction: zod_1.z.nativeEnum(client_1.PaymentDirection).optional(),
    invoiceId: zod_1.z.string().nullable().optional(),
    customerId: zod_1.z.string().nullable().optional(),
    supplierId: zod_1.z.string().nullable().optional(),
    currencyId: zod_1.z.string().nullable().optional(),
    cashBoxId: zod_1.z.string().nullable().optional(),
    method: zod_1.z.nativeEnum(client_1.PaymentMethod).optional(),
    amount: zod_1.z.number().positive(),
    reference: zod_1.z.string().nullable().optional(),
    note: zod_1.z.string().nullable().optional(),
    paidAt: zod_1.z.coerce.date().nullable().optional(),
});
const updateSchema = zod_1.z.object({
    amount: zod_1.z.number().positive().optional(),
    cashBoxId: zod_1.z.string().nullable().optional(),
    reference: zod_1.z.string().nullable().optional(),
    note: zod_1.z.string().nullable().optional(),
    paidAt: zod_1.z.coerce.date().nullable().optional(),
});
const serializePayment = (payment) => ({
    ...payment,
    amount: Number(payment.amount),
    invoice: payment.invoice
        ? { ...payment.invoice, total: Number(payment.invoice.total), balance: Number(payment.invoice.balance) }
        : null,
});
router.get('/', (0, authorize_1.requirePermission)('payments.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 25);
    const customerId = (0, query_1.asString)(query.customerId);
    const supplierId = (0, query_1.asString)(query.supplierId);
    const invoiceId = (0, query_1.asString)(query.invoiceId);
    const cashBoxId = (0, query_1.asString)(query.cashBoxId);
    const direction = (0, query_1.asEnum)(query.direction, directions);
    const method = (0, query_1.asEnum)(query.method, methods);
    const includeCancelled = (0, query_1.asBool)(query.includeCancelled) === true;
    const from = (0, query_1.asDate)(query.from);
    const to = (0, query_1.asDate)(query.to);
    const where = {};
    if (!includeCancelled)
        where.cancelledAt = null;
    if (customerId)
        where.customerId = customerId;
    if (supplierId)
        where.supplierId = supplierId;
    if (invoiceId)
        where.invoiceId = invoiceId;
    if (cashBoxId)
        where.cashBoxId = cashBoxId;
    if (direction)
        where.direction = direction;
    if (method)
        where.method = method;
    if (from || to) {
        where.paidAt = { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) };
    }
    const [total, payments] = await Promise.all([
        prisma_1.prisma.payment.count({ where }),
        prisma_1.prisma.payment.findMany({
            where,
            orderBy: { paidAt: 'desc' },
            skip: paging.skip,
            take: paging.take,
            include: payments_service_1.paymentInclude,
        }),
    ]);
    (0, http_1.paginated)(res, payments.map((payment) => serializePayment(payment)), total, paging);
}));
router.post('/', (0, authorize_1.requirePermission)('payments.write'), (0, validate_1.validateBody)(createSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const payment = await (0, payments_service_1.createPayment)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, serializePayment(payment));
}));
router.patch('/:id', (0, authorize_1.requirePermission)('treasury.write'), (0, validate_1.validateBody)(updateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const payment = await (0, payments_service_1.updatePayment)(req.params.id, req.body, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.ok)(res, serializePayment(payment));
}));
router.post('/:id/cancel', (0, authorize_1.requirePermission)('treasury.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const payment = await (0, payments_service_1.cancelPayment)(req.params.id, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.ok)(res, serializePayment(payment));
}));
exports.default = router;
//# sourceMappingURL=payments.routes.js.map