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
const payments_service_1 = require("../payments/payments.service");
const treasury_service_1 = require("./treasury.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const boxSchema = zod_1.z.object({
    code: zod_1.z.string().min(1).max(20),
    name: zod_1.z.string().min(1).max(120),
    type: zod_1.z.nativeEnum(client_1.CashBoxType).optional(),
    openingBalance: zod_1.z.number().optional(),
    active: zod_1.z.boolean().optional(),
    isDefault: zod_1.z.boolean().optional(),
});
const boxUpdateSchema = boxSchema.partial();
const transferSchema = zod_1.z.object({
    fromBoxId: zod_1.z.string().min(1),
    toBoxId: zod_1.z.string().min(1),
    amount: zod_1.z.number().positive(),
    exchangeRate: zod_1.z.number().positive().optional(),
    reference: zod_1.z.string().nullable().optional(),
    note: zod_1.z.string().nullable().optional(),
    transferDate: zod_1.z.coerce.date().nullable().optional(),
});
const transferUpdateSchema = zod_1.z.object({
    amount: zod_1.z.number().positive().optional(),
    reference: zod_1.z.string().nullable().optional(),
    note: zod_1.z.string().nullable().optional(),
    transferDate: zod_1.z.coerce.date().nullable().optional(),
});
const collectionSchema = zod_1.z.object({
    cashBoxId: zod_1.z.string().nullable().optional(),
    salespersonId: zod_1.z.string().nullable().optional(),
    collectedAt: zod_1.z.coerce.date().nullable().optional(),
    reference: zod_1.z.string().nullable().optional(),
    note: zod_1.z.string().nullable().optional(),
    lines: zod_1.z
        .array(zod_1.z.object({
        customerId: zod_1.z.string().nullable().optional(),
        invoiceId: zod_1.z.string().nullable().optional(),
        cashBoxId: zod_1.z.string().nullable().optional(),
        amount: zod_1.z.number().positive(),
        note: zod_1.z.string().nullable().optional(),
    }))
        .min(1),
});
const serializeBox = (box) => ({
    ...box,
    openingBalance: Number(box.openingBalance),
    ...(box.balance !== undefined ? { balance: Number(box.balance) } : {}),
});
const serializeTransfer = (transfer) => ({
    ...transfer,
    amount: Number(transfer.amount),
    exchangeRate: Number(transfer.exchangeRate),
});
const serializeCollection = (voucher) => ({
    ...voucher,
    total: Number(voucher.total),
    lines: voucher.lines.map((line) => ({
        ...line,
        amount: Number(line.amount),
        invoice: line.invoice
            ? { ...line.invoice, total: Number(line.invoice.total), balance: Number(line.invoice.balance) }
            : null,
    })),
    payments: voucher.payments.map((payment) => ({ ...payment, amount: Number(payment.amount) })),
});
// --- cash boxes -------------------------------------------------------------
router.get('/boxes', (0, authorize_1.requirePermission)('treasury.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    const boxes = await (0, treasury_service_1.listCashBoxes)();
    (0, http_1.ok)(res, boxes.map(serializeBox));
}));
router.post('/boxes', (0, authorize_1.requirePermission)('treasury.write'), (0, validate_1.validateBody)(boxSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const box = await (0, treasury_service_1.createCashBox)(req.body, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.created)(res, serializeBox(box));
}));
router.get('/boxes/:id', (0, authorize_1.requirePermission)('treasury.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const box = await (0, treasury_service_1.getCashBox)(req.params.id);
    (0, http_1.ok)(res, serializeBox(box));
}));
router.patch('/boxes/:id', (0, authorize_1.requirePermission)('treasury.write'), (0, validate_1.validateBody)(boxUpdateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const box = await (0, treasury_service_1.updateCashBox)(req.params.id, req.body, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.ok)(res, serializeBox(box));
}));
router.delete('/boxes/:id', (0, authorize_1.requirePermission)('treasury.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const result = await (0, treasury_service_1.deleteCashBox)(req.params.id);
    (0, http_1.ok)(res, result);
}));
router.get('/boxes/:id/statement', (0, authorize_1.requirePermission)('treasury.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const statement = await (0, treasury_service_1.buildCashBoxStatement)(req.params.id, from, to);
    (0, http_1.ok)(res, statement);
}));
// --- transfers --------------------------------------------------------------
router.get('/transfers', (0, authorize_1.requirePermission)('treasury.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const boxId = (0, query_1.asString)(query.boxId);
    const from = (0, query_1.asDate)(query.from);
    const to = (0, query_1.asDate)(query.to);
    // Paged mode: used by the treasury "التحويلات" tab for lazy loading.
    if ((0, query_1.asBool)(query.paged) === true) {
        const paging = (0, http_1.getPaging)(query, 25);
        const result = await (0, treasury_service_1.listTransfers)({
            boxId,
            from,
            to,
            limit: paging.take,
            skip: paging.skip,
            includeCancelled: (0, query_1.asBool)(query.includeCancelled) === true,
            paged: true,
        });
        (0, http_1.paginated)(res, result.items.map(serializeTransfer), result.total, paging);
        return;
    }
    const transfers = await (0, treasury_service_1.listTransfers)({ boxId, from, to });
    (0, http_1.ok)(res, transfers.map(serializeTransfer));
}));
router.post('/transfers', (0, authorize_1.requirePermission)('treasury.write'), (0, validate_1.validateBody)(transferSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const transfer = await (0, treasury_service_1.createTransfer)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, serializeTransfer(transfer));
}));
router.patch('/transfers/:id', (0, authorize_1.requirePermission)('treasury.write'), (0, validate_1.validateBody)(transferUpdateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const transfer = await (0, treasury_service_1.updateTransfer)(req.params.id, req.body);
    (0, http_1.ok)(res, serializeTransfer(transfer));
}));
router.post('/transfers/:id/cancel', (0, authorize_1.requirePermission)('treasury.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const transfer = await (0, treasury_service_1.cancelTransfer)(req.params.id, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.ok)(res, serializeTransfer(transfer));
}));
// --- agent collection receipts ---------------------------------------------
router.get('/collections', (0, authorize_1.requirePermission)('payments.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 25);
    const includeCancelled = (0, query_1.asBool)(query.includeCancelled) === true;
    const salespersonId = (0, query_1.asString)(query.salespersonId);
    const customerId = (0, query_1.asString)(query.customerId);
    const from = (0, query_1.asDate)(query.from);
    const to = (0, query_1.asDate)(query.to);
    const toBound = to ? (0, treasury_service_1.inclusiveEnd)(to) : undefined;
    const where = {};
    if (!includeCancelled)
        where.cancelledAt = null;
    if (salespersonId)
        where.salespersonId = salespersonId;
    if (customerId)
        where.lines = { some: { customerId } };
    if (from || toBound) {
        where.collectedAt = { ...(from ? { gte: from } : {}), ...(toBound ? { lte: toBound } : {}) };
    }
    const [total, vouchers] = await Promise.all([
        prisma_1.prisma.collectionVoucher.count({ where }),
        prisma_1.prisma.collectionVoucher.findMany({
            where,
            include: payments_service_1.collectionInclude,
            orderBy: [{ collectedAt: 'desc' }, { createdAt: 'desc' }],
            skip: paging.skip,
            take: paging.take,
        }),
    ]);
    (0, http_1.paginated)(res, vouchers.map(serializeCollection), total, paging);
}));
router.post('/collections', (0, authorize_1.requirePermission)('payments.write'), (0, validate_1.validateBody)(collectionSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const voucher = await (0, payments_service_1.createCollection)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, serializeCollection(voucher));
}));
router.get('/collections/:id', (0, authorize_1.requirePermission)('payments.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const voucher = await prisma_1.prisma.collectionVoucher.findUnique({
        where: { id: req.params.id },
        include: payments_service_1.collectionInclude,
    });
    if (!voucher) {
        res.status(404).json({ error: { message: 'Collection receipt not found', code: 'NOT_FOUND' } });
        return;
    }
    (0, http_1.ok)(res, serializeCollection(voucher));
}));
router.post('/collections/:id/cancel', (0, authorize_1.requirePermission)('treasury.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const voucher = await (0, payments_service_1.cancelCollection)(req.params.id, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.ok)(res, serializeCollection(voucher));
}));
exports.default = router;
//# sourceMappingURL=treasury.routes.js.map