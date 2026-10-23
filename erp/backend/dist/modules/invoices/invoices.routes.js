"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const api_error_1 = require("../../lib/api-error");
const http_1 = require("../../lib/http");
const prisma_1 = require("../../lib/prisma");
const money_1 = require("../../lib/money");
const query_1 = require("../../lib/query");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const permissions_1 = require("../../lib/permissions");
const invoices_service_1 = require("./invoices.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const statuses = ['DRAFT', 'ISSUED', 'PARTIALLY_PAID', 'PAID', 'VOID'];
const lineSchema = zod_1.z.object({
    productId: zod_1.z.string().nullable().optional(),
    description: zod_1.z.string().optional(),
    quantity: zod_1.z.number().int().positive(),
    unitPrice: zod_1.z.number().min(0),
    discount: zod_1.z.number().min(0).optional(),
    taxRate: zod_1.z.number().min(0).max(100).optional(),
});
const createSchema = zod_1.z
    .object({
    salesOrderId: zod_1.z.string().nullable().optional(),
    customerId: zod_1.z.string().nullable().optional(),
    currencyId: zod_1.z.string().nullable().optional(),
    dueDate: zod_1.z.coerce.date().nullable().optional(),
    notes: zod_1.z.string().nullable().optional(),
    lines: zod_1.z.array(lineSchema).min(1).optional(),
    skipUnavailable: zod_1.z.boolean().optional(),
    issue: zod_1.z.boolean().optional(),
})
    .refine((value) => Boolean(value.salesOrderId) || (value.lines && value.lines.length > 0), {
    message: 'Provide either salesOrderId or at least one line',
    path: ['lines'],
});
const updateSchema = zod_1.z
    .object({
    customerId: zod_1.z.string().nullable().optional(),
    currencyId: zod_1.z.string().nullable().optional(),
    dueDate: zod_1.z.coerce.date().nullable().optional(),
    notes: zod_1.z.string().nullable().optional(),
    lines: zod_1.z.array(lineSchema).min(1).optional(),
});
const serializeInvoice = (invoice) => ({
    ...invoice,
    subtotal: Number(invoice.subtotal),
    discountTotal: Number(invoice.discountTotal),
    taxTotal: Number(invoice.taxTotal),
    total: Number(invoice.total),
    amountPaid: Number(invoice.amountPaid),
    balance: Number(invoice.balance),
    exchangeRate: Number(invoice.exchangeRate),
});
router.get('/', (0, authorize_1.requirePermission)('invoices.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 25);
    const customerId = (0, query_1.asString)(query.customerId);
    const status = (0, query_1.asEnum)(query.status, statuses);
    const search = (0, query_1.asString)(query.search);
    const from = (0, query_1.asDate)(query.from);
    const to = (0, query_1.asDate)(query.to);
    const unpaidOnly = (0, query_1.asString)(query.unpaid) === 'true';
    const where = {};
    if (customerId)
        where.customerId = customerId;
    if (status)
        where.status = status;
    if (unpaidOnly)
        where.status = { in: ['ISSUED', 'PARTIALLY_PAID'] };
    if (search) {
        where.OR = [
            { number: { contains: search, mode: 'insensitive' } },
            { customer: { name: { contains: search, mode: 'insensitive' } } },
        ];
    }
    if (from || to) {
        where.issueDate = { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) };
    }
    const [total, invoices] = await Promise.all([
        prisma_1.prisma.invoice.count({ where }),
        prisma_1.prisma.invoice.findMany({
            where,
            orderBy: { issueDate: 'desc' },
            skip: paging.skip,
            take: paging.take,
            include: {
                customer: { select: { id: true, name: true } },
                currency: { select: { id: true, code: true, symbol: true } },
                _count: { select: { lines: true, payments: true } },
            },
        }),
    ]);
    (0, http_1.paginated)(res, invoices.map((invoice) => serializeInvoice(invoice)), total, paging);
}));
router.get('/preview-from-order/:orderId', (0, authorize_1.requirePermission)('invoices.read'), (0, http_1.asyncHandler)(async (req, res) => {
    (0, http_1.ok)(res, await (0, invoices_service_1.previewInvoiceFromOrder)(req.params.orderId));
}));
router.get('/:id', (0, authorize_1.requirePermission)('invoices.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const invoice = await prisma_1.prisma.invoice.findUnique({
        where: { id: req.params.id },
        include: invoices_service_1.invoiceInclude,
    });
    if (!invoice)
        throw api_error_1.ApiError.notFound('Invoice not found');
    // What the customer owed before this invoice. The stored customer balance
    // only counts ISSUED/PARTIALLY_PAID/PAID invoices, so a draft contributes
    // nothing and the whole balance is "previous"; for an issued invoice its own
    // outstanding balance is subtracted.
    const counted = ['ISSUED', 'PARTIALLY_PAID', 'PAID'].includes(invoice.status);
    const previousBalance = invoice.customer
        ? (0, money_1.round2)(Number(invoice.customer.balance) - (counted ? Number(invoice.balance) : 0))
        : 0;
    (0, http_1.ok)(res, { ...serializeInvoice(invoice), previousBalance });
}));
router.post('/', (0, authorize_1.requirePermission)('invoices.write'), (0, validate_1.validateBody)(createSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const invoice = await (0, invoices_service_1.createInvoice)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, serializeInvoice(invoice));
}));
router.post('/:id/issue', (0, authorize_1.requirePermission)('invoices.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const invoice = await (0, invoices_service_1.issueInvoice)(req.params.id, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.ok)(res, serializeInvoice(invoice));
}));
router.patch('/:id', (0, authorize_1.requirePermission)('invoices.write'), (0, validate_1.validateBody)(updateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const user = (0, authenticate_1.currentUser)(req);
    // Draft invoices may be edited by whoever is entering them; once issued only
    // an administrator may change them.
    const existing = await prisma_1.prisma.invoice.findUnique({
        where: { id: req.params.id },
        select: { status: true },
    });
    if (existing &&
        existing.status !== 'DRAFT' &&
        (user.role ?? '').toUpperCase() !== 'ADMIN') {
        throw api_error_1.ApiError.forbidden('Only an administrator can edit an issued invoice');
    }
    const invoice = await (0, invoices_service_1.updateInvoice)(req.params.id, req.body, {
        allowPosted: (0, permissions_1.roleHasPermission)(user.role, 'invoices.edit'),
        userId: user.id,
    });
    (0, http_1.ok)(res, serializeInvoice(invoice));
}));
router.post('/:id/void', (0, authorize_1.requirePermission)('invoices.cancel'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const invoice = await (0, invoices_service_1.voidInvoice)(req.params.id, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.ok)(res, serializeInvoice(invoice));
}));
exports.default = router;
//# sourceMappingURL=invoices.routes.js.map