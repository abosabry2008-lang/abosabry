"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const client_1 = require("@prisma/client");
const express_1 = require("express");
const zod_1 = require("zod");
const http_1 = require("../../lib/http");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const invoices_service_1 = require("../invoices/invoices.service");
const payments_service_1 = require("../payments/payments.service");
const sales_service_1 = require("../sales/sales.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const saleSchema = zod_1.z.object({
    customerId: zod_1.z.string().nullable().optional(),
    warehouseId: zod_1.z.string().min(1),
    currencyId: zod_1.z.string().nullable().optional(),
    method: zod_1.z.nativeEnum(client_1.PaymentMethod).default('CASH'),
    paidAmount: zod_1.z.number().min(0),
    reference: zod_1.z.string().nullable().optional(),
    notes: zod_1.z.string().nullable().optional(),
    lines: zod_1.z
        .array(zod_1.z.object({
        productId: zod_1.z.string().min(1),
        quantity: zod_1.z.number().int().positive(),
        unitPrice: zod_1.z.number().min(0).optional(),
        discount: zod_1.z.number().min(0).optional(),
        taxRate: zod_1.z.number().min(0).max(100).optional(),
        sellUnit: zod_1.z.enum(['unit', 'box', 'carton']).optional(),
    }))
        .min(1),
});
/**
 * One-shot point-of-sale transaction: creates and fulfils a sales order,
 * raises and issues the invoice, then records the payment - atomically.
 */
router.post('/sale', (0, authorize_1.requirePermission)('pos.use'), (0, validate_1.validateBody)(saleSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const userId = (0, authenticate_1.currentUser)(req).id;
    const result = await prisma_1.prisma.$transaction(async (tx) => {
        const salesOrder = await (0, sales_service_1.registerSaleTx)(tx, {
            customerId: req.body.customerId ?? null,
            warehouseId: req.body.warehouseId,
            currencyId: req.body.currencyId ?? null,
            notes: req.body.notes ?? null,
            channel: 'POS',
            lines: req.body.lines,
        }, userId);
        const draft = await (0, invoices_service_1.createInvoiceTx)(tx, { salesOrderId: salesOrder.id, userId });
        const invoice = await (0, invoices_service_1.issueInvoiceTx)(tx, draft.id, userId);
        const total = (0, money_1.round2)(Number(invoice.total));
        const paidAmount = (0, money_1.round2)(Number(req.body.paidAmount));
        const applied = (0, money_1.round2)(Math.min(paidAmount, total));
        const payment = applied > 0
            ? await (0, payments_service_1.createPaymentTx)(tx, {
                invoiceId: invoice.id,
                amount: applied,
                method: req.body.method,
                reference: req.body.reference ?? null,
                paidAt: new Date(),
                userId,
            })
            : null;
        const finalInvoice = await tx.invoice.findUnique({
            where: { id: invoice.id },
            include: invoices_service_1.invoiceInclude,
        });
        return {
            salesOrder,
            invoice: finalInvoice,
            payment,
            change: (0, money_1.round2)(Math.max(0, paidAmount - total)),
            outstanding: (0, money_1.round2)(Math.max(0, total - applied)),
        };
    });
    (0, http_1.created)(res, result);
}));
exports.default = router;
//# sourceMappingURL=pos.routes.js.map