"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.invoiceInclude = void 0;
exports.recalcCustomerBalance = recalcCustomerBalance;
exports.previewInvoiceFromOrder = previewInvoiceFromOrder;
exports.createInvoiceTx = createInvoiceTx;
exports.issueInvoiceTx = issueInvoiceTx;
exports.voidInvoiceTx = voidInvoiceTx;
exports.createInvoice = createInvoice;
exports.issueInvoice = issueInvoice;
exports.voidInvoice = voidInvoice;
exports.updateInvoiceTx = updateInvoiceTx;
exports.updateInvoice = updateInvoice;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const sequence_1 = require("../../lib/sequence");
const settings_1 = require("../../lib/settings");
const accounting_service_1 = require("../accounting/accounting.service");
exports.invoiceInclude = {
    customer: { select: { id: true, name: true, email: true, phone: true, address: true, balance: true } },
    currency: { select: { id: true, code: true, symbol: true } },
    salesOrder: { select: { id: true, number: true } },
    lines: {
        include: {
            product: {
                select: {
                    id: true,
                    sku: true,
                    name: true,
                    unit: true,
                    boxesPerCarton: true,
                    boxPrice: true,
                    cartonPrice: true,
                    salePrice: true,
                    costPrice: true,
                },
            },
        },
    },
    payments: {
        where: { cancelledAt: null },
        select: { id: true, number: true, amount: true, method: true, paidAt: true, reference: true },
    },
};
/**
 * Opening balance recorded for a single customer, summed from the two places it
 * can come from:
 *  - the `OPENING_CUSTOMER` journal posted when the customer is created, and
 *  - the per-customer amounts inside a bulk opening-balance document
 *    (`OpeningBalance.details.customers`).
 */
async function customerOpeningBalance(tx, customerId) {
    const [lines, docs] = await Promise.all([
        tx.journalLine.findMany({
            where: {
                account: { code: '1100' },
                journalEntry: { sourceType: 'OPENING_CUSTOMER', sourceId: customerId },
            },
            select: { debit: true, credit: true },
        }),
        tx.openingBalance.findMany({ where: { cancelledAt: null }, select: { details: true } }),
    ]);
    let total = lines.reduce((sum, line) => sum + Number(line.debit) - Number(line.credit), 0);
    for (const doc of docs) {
        const details = doc.details;
        for (const row of details?.customers ?? []) {
            if (row.customerId === customerId)
                total += Number(row.amount ?? 0);
        }
    }
    return (0, money_1.round2)(total);
}
/**
 * Recomputes a customer's outstanding balance from their open invoices, any
 * live account settlements (تسويات) and their opening balance.
 *
 * The opening balance is not stored on the customer row itself, so it is read
 * back from the ledger. Without it every recalculation (issued invoice, payment,
 * settlement) silently wiped the opening balance.
 */
async function recalcCustomerBalance(tx, customerId) {
    const [aggregate, settlements, openingBalance] = await Promise.all([
        tx.invoice.aggregate({
            where: {
                customerId,
                status: { in: ['ISSUED', 'PARTIALLY_PAID', 'PAID'] },
            },
            _sum: { balance: true },
        }),
        tx.accountSettlement.findMany({
            where: { customerId, cancelledAt: null },
            select: { direction: true, amount: true },
        }),
        customerOpeningBalance(tx, customerId),
    ]);
    const invoiceBalance = Number(aggregate._sum.balance ?? 0);
    const adjustment = settlements.reduce((sum, row) => {
        const amount = Number(row.amount);
        return sum + (row.direction === 'INCREASE' ? amount : -amount);
    }, 0);
    await tx.customer.update({
        where: { id: customerId },
        data: { balance: (0, money_1.round2)(openingBalance + invoiceBalance + adjustment) },
    });
}
/** Quantity of a product on hand across all stock levels of a warehouse. */
async function stockOnHand(tx, warehouseId, productId) {
    const levels = await tx.stockLevel.findMany({
        where: { productId, location: { warehouseId } },
        select: { quantity: true },
    });
    return levels.reduce((sum, level) => sum + Number(level.quantity), 0);
}
/**
 * Shows, before invoicing a sales order, which of its lines are short on stock
 * so the operator can choose to invoice only what is available or everything.
 */
async function previewInvoiceFromOrder(salesOrderId) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const order = await tx.salesOrder.findUnique({
            where: { id: salesOrderId },
            include: { lines: { include: { product: { select: { id: true, name: true, sku: true } } } } },
        });
        if (!order)
            throw api_error_1.ApiError.notFound('Sales order not found');
        const lines = [];
        for (const line of order.lines) {
            const available = await stockOnHand(tx, order.warehouseId, line.productId);
            lines.push({
                lineId: line.id,
                productId: line.productId,
                productName: line.product.name,
                sku: line.product.sku,
                quantity: line.quantity,
                available,
                shortfall: Math.max(0, line.quantity - available),
            });
        }
        const totals = lines.reduce((acc, line) => ({
            quantity: acc.quantity + line.quantity,
            available: acc.available + line.available,
            shortfall: acc.shortfall + line.shortfall,
        }), { quantity: 0, available: 0, shortfall: 0 });
        return {
            salesOrderId: order.id,
            orderNumber: order.number,
            canInvoiceEverything: totals.shortfall === 0,
            lines,
            totals,
        };
    });
}
async function buildFromSalesOrder(tx, salesOrderId, taxEnabled = true, skipUnavailable = false) {
    const order = await tx.salesOrder.findUnique({
        where: { id: salesOrderId },
        include: { lines: { include: { product: true } } },
    });
    if (!order)
        throw api_error_1.ApiError.notFound('Sales order not found');
    if (order.status === 'DRAFT' || order.status === 'CANCELLED') {
        throw api_error_1.ApiError.badRequest('Only confirmed sales orders can be invoiced', 'NOT_INVOICEABLE');
    }
    const existing = await tx.invoice.findFirst({
        where: { salesOrderId, status: { not: 'VOID' } },
    });
    if (existing) {
        throw api_error_1.ApiError.conflict(`Sales order ${order.number} already has invoice ${existing.number}`, 'ALREADY_INVOICED');
    }
    const lines = [];
    for (const line of order.lines) {
        if (skipUnavailable) {
            const available = await stockOnHand(tx, order.warehouseId, line.productId);
            if (available < line.quantity)
                continue;
        }
        const taxRate = taxEnabled ? Number(line.taxRate) : 0;
        const total = (0, money_1.lineTotals)({
            quantity: line.quantity,
            unitPrice: Number(line.unitPrice),
            discount: Number(line.discount),
            taxRate,
        }).total;
        lines.push({
            productId: line.productId,
            description: line.product?.name ?? 'Item',
            quantity: line.quantity,
            unitPrice: Number(line.unitPrice),
            discount: Number(line.discount),
            taxRate,
            total,
            sellUnit: line.sellUnit ?? 'unit',
        });
    }
    if (lines.length === 0) {
        throw api_error_1.ApiError.badRequest('Every line of this order is short on stock — nothing is available to invoice', 'NOTHING_AVAILABLE');
    }
    return {
        customerId: order.customerId,
        currencyId: order.currencyId,
        exchangeRate: await exchangeRateFor(tx, order.currencyId),
        notes: order.notes,
        dueDate: null,
        lines,
        totals: (0, money_1.documentTotals)(lines.map((line) => ({
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            discount: line.discount,
            taxRate: line.taxRate,
        }))),
    };
}
async function buildFromLines(input, taxEnabled = true) {
    const provided = input.lines ?? [];
    if (provided.length === 0) {
        throw api_error_1.ApiError.badRequest('An invoice needs either a salesOrderId or at least one line');
    }
    const lines = provided.map((line) => {
        const taxRate = taxEnabled ? line.taxRate ?? 0 : 0;
        const totals = (0, money_1.lineTotals)({
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            discount: line.discount,
            taxRate,
        });
        return {
            productId: line.productId ?? null,
            description: line.description ?? 'Item',
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            discount: line.discount ?? 0,
            taxRate,
            total: totals.total,
            sellUnit: line.sellUnit ?? 'unit',
        };
    });
    return {
        customerId: input.customerId ?? null,
        currencyId: input.currencyId ?? null,
        exchangeRate: 1,
        notes: input.notes ?? null,
        dueDate: input.dueDate ?? null,
        lines,
        totals: (0, money_1.documentTotals)(lines.map((line) => ({
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            discount: line.discount,
            taxRate: line.taxRate,
        }))),
    };
}
async function exchangeRateFor(tx, currencyId) {
    if (!currencyId)
        return 1;
    const currency = await tx.currency.findUnique({ where: { id: currencyId } });
    return currency ? Number(currency.exchangeRate) : 1;
}
/** Posts the receivable / revenue / tax / COGS journal entry for an invoice. */
async function postInvoiceJournalTx(tx, invoice, userId) {
    const total = (0, money_1.round2)(Number(invoice.total));
    const subtotal = (0, money_1.round2)(Number(invoice.subtotal));
    const taxTotal = (0, money_1.round2)(Number(invoice.taxTotal));
    // Cost of goods sold from the products on the invoice.
    const productIds = invoice.lines.map((line) => line.productId).filter((v) => Boolean(v));
    const products = productIds.length
        ? await tx.product.findMany({ where: { id: { in: productIds } }, select: { id: true, costPrice: true } })
        : [];
    const costById = new Map(products.map((product) => [product.id, Number(product.costPrice)]));
    const cogs = (0, money_1.round2)(invoice.lines.reduce((sum, line) => {
        if (!line.productId)
            return sum;
        return sum + line.quantity * (costById.get(line.productId) ?? 0);
    }, 0));
    const journalLines = [
        { accountCode: accounting_service_1.ACCOUNT.RECEIVABLE, debit: total, description: `Invoice ${invoice.number}` },
        { accountCode: accounting_service_1.ACCOUNT.REVENUE, credit: subtotal, description: `Revenue ${invoice.number}` },
        { accountCode: accounting_service_1.ACCOUNT.TAX_PAYABLE, credit: taxTotal, description: `Tax on ${invoice.number}` },
    ];
    if (cogs > 0) {
        journalLines.push({ accountCode: accounting_service_1.ACCOUNT.COGS, debit: cogs, description: `Cost of sales ${invoice.number}` }, { accountCode: accounting_service_1.ACCOUNT.INVENTORY, credit: cogs, description: `Inventory reduction ${invoice.number}` });
    }
    await (0, accounting_service_1.postJournal)(tx, {
        memo: `Invoice ${invoice.number} issued`,
        reference: invoice.number,
        sourceType: 'INVOICE',
        sourceId: invoice.id,
        userId,
        lines: journalLines,
    });
}
async function createInvoiceTx(tx, input) {
    const taxEnabled = await (0, settings_1.isTaxEnabled)();
    const built = input.salesOrderId
        ? await buildFromSalesOrder(tx, input.salesOrderId, taxEnabled, input.skipUnavailable === true)
        : await buildFromLines(input, taxEnabled);
    const exchangeRate = input.salesOrderId ? built.exchangeRate : await exchangeRateFor(tx, built.currencyId);
    const settings = await (0, settings_1.getSettings)(tx);
    const number = await (0, sequence_1.nextNumber)(tx, 'invoice', settings.invoicePrefix ?? 'INV');
    return tx.invoice.create({
        data: {
            number,
            customerId: built.customerId,
            salesOrderId: input.salesOrderId ?? null,
            currencyId: built.currencyId,
            status: 'DRAFT',
            dueDate: built.dueDate,
            notes: built.notes,
            exchangeRate,
            subtotal: built.totals.subtotal,
            discountTotal: built.totals.discountTotal,
            taxTotal: built.totals.taxTotal,
            total: built.totals.total,
            amountPaid: 0,
            balance: built.totals.total,
            lines: {
                create: built.lines.map((line) => ({
                    productId: line.productId,
                    description: line.description,
                    quantity: line.quantity,
                    unitPrice: line.unitPrice,
                    discount: line.discount,
                    taxRate: line.taxRate,
                    total: line.total,
                    sellUnit: line.sellUnit ?? 'unit',
                })),
            },
        },
        include: exports.invoiceInclude,
    });
}
async function issueInvoiceTx(tx, id, userId) {
    const invoice = await tx.invoice.findUnique({ where: { id }, include: { lines: true } });
    if (!invoice)
        throw api_error_1.ApiError.notFound('Invoice not found');
    if (invoice.status !== 'DRAFT') {
        throw api_error_1.ApiError.badRequest(`Only draft invoices can be issued (current status: ${invoice.status})`, 'NOT_ISSUABLE');
    }
    const updated = await tx.invoice.update({
        where: { id },
        data: { status: 'ISSUED', issueDate: new Date() },
        include: exports.invoiceInclude,
    });
    await postInvoiceJournalTx(tx, invoice, userId);
    if (invoice.customerId)
        await recalcCustomerBalance(tx, invoice.customerId);
    return updated;
}
async function voidInvoiceTx(tx, id, userId) {
    const invoice = await tx.invoice.findUnique({ where: { id }, include: { payments: true } });
    if (!invoice)
        throw api_error_1.ApiError.notFound('Invoice not found');
    if (invoice.status === 'VOID')
        throw api_error_1.ApiError.badRequest('This invoice is already void');
    // Cancelling an invoice also cancels every live payment recorded against it,
    // so cash-box balances, the ledger and the customer account stay consistent.
    for (const payment of invoice.payments) {
        if (payment.cancelledAt)
            continue;
        if (payment.collectionVoucherId) {
            throw api_error_1.ApiError.badRequest('This invoice was paid through a collection receipt — cancel the receipt first', 'COLLECTION_PAYMENT');
        }
        await (0, accounting_service_1.reverseJournalBySource)(tx, {
            sourceType: 'PAYMENT',
            sourceId: payment.id,
            reversalSourceType: 'PAYMENT_CANCEL',
            memo: `Payment ${payment.number} cancelled`,
            reference: payment.number,
            userId,
        });
        await tx.payment.update({
            where: { id: payment.id },
            data: { cancelledAt: new Date(), cancelledBy: userId ?? null },
        });
        if (payment.supplierId && payment.direction === 'OUTBOUND') {
            await tx.supplier.update({
                where: { id: payment.supplierId },
                data: { balance: { increment: (0, money_1.round2)(Number(payment.amount)) } },
            });
        }
    }
    const wasIssued = invoice.status !== 'DRAFT';
    const updated = await tx.invoice.update({
        where: { id },
        data: { status: 'VOID', balance: 0, amountPaid: 0 },
        include: exports.invoiceInclude,
    });
    if (wasIssued) {
        // Exact reversal of the issue entry, including the COGS / Inventory legs.
        await (0, accounting_service_1.reverseJournalBySource)(tx, {
            sourceType: 'INVOICE',
            sourceId: invoice.id,
            reversalSourceType: 'INVOICE_VOID',
            memo: `Invoice ${invoice.number} voided`,
            reference: invoice.number,
            userId,
        });
    }
    if (invoice.customerId)
        await recalcCustomerBalance(tx, invoice.customerId);
    return updated;
}
// ---------------------------------------------------------------------------
// Route-facing wrappers
// ---------------------------------------------------------------------------
async function createInvoice(input) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const invoice = await createInvoiceTx(tx, input);
        if (!input.issue)
            return invoice;
        return issueInvoiceTx(tx, invoice.id, input.userId);
    });
}
async function issueInvoice(id, userId) {
    return prisma_1.prisma.$transaction((tx) => issueInvoiceTx(tx, id, userId));
}
async function voidInvoice(id, userId) {
    return prisma_1.prisma.$transaction((tx) => voidInvoiceTx(tx, id, userId));
}
async function updateInvoiceTx(tx, id, input, options = {}) {
    const invoice = await tx.invoice.findUnique({ where: { id } });
    if (!invoice)
        throw api_error_1.ApiError.notFound('Invoice not found');
    const isDraft = invoice.status === 'DRAFT';
    const isPosted = options.allowPosted === true &&
        (invoice.status === 'ISSUED' || invoice.status === 'PARTIALLY_PAID' || invoice.status === 'PAID');
    if (!isDraft && !isPosted) {
        throw api_error_1.ApiError.badRequest('Only draft invoices can be updated', 'NOT_EDITABLE');
    }
    if (isPosted) {
        const livePayments = await tx.payment.count({ where: { invoiceId: id, cancelledAt: null } });
        if (livePayments > 0) {
            throw api_error_1.ApiError.conflict('Cancel the payments recorded against this invoice before editing it', 'HAS_PAYMENTS');
        }
    }
    const built = input.lines && input.lines.length > 0
        ? await buildFromLines({
            ...input,
            lines: input.lines,
        }, await (0, settings_1.isTaxEnabled)())
        : {
            customerId: input.customerId ?? invoice.customerId,
            currencyId: input.currencyId ?? invoice.currencyId,
            exchangeRate: await exchangeRateFor(tx, input.currencyId ?? invoice.currencyId),
            notes: input.notes ?? invoice.notes,
            dueDate: input.dueDate ?? invoice.dueDate,
            lines: [],
            totals: {
                subtotal: Number(invoice.subtotal),
                discountTotal: Number(invoice.discountTotal),
                taxTotal: Number(invoice.taxTotal),
                total: Number(invoice.total),
            },
        };
    const exchangeRate = built.lines.length > 0
        ? await exchangeRateFor(tx, built.currencyId)
        : built.exchangeRate;
    const data = {};
    if (input.customerId !== undefined) {
        data.customer = input.customerId ? { connect: { id: input.customerId } } : { disconnect: true };
    }
    if (input.currencyId !== undefined) {
        data.currency = input.currencyId ? { connect: { id: input.currencyId } } : { disconnect: true };
    }
    if (input.notes !== undefined)
        data.notes = input.notes;
    if (input.dueDate !== undefined)
        data.dueDate = input.dueDate;
    data.exchangeRate = exchangeRate;
    if (built.lines.length > 0) {
        await tx.invoiceLine.deleteMany({ where: { invoiceId: id } });
        data.subtotal = built.totals.subtotal;
        data.discountTotal = built.totals.discountTotal;
        data.taxTotal = built.totals.taxTotal;
        data.total = built.totals.total;
        data.balance = built.totals.total;
        if (isPosted) {
            data.amountPaid = 0;
            data.status = 'ISSUED';
        }
        data.lines = {
            create: built.lines.map((line) => ({
                productId: line.productId,
                description: line.description,
                quantity: line.quantity,
                unitPrice: line.unitPrice,
                discount: line.discount,
                taxRate: line.taxRate,
                total: line.total,
                sellUnit: line.sellUnit ?? 'unit',
            })),
        };
    }
    const updated = await tx.invoice.update({ where: { id }, data, include: exports.invoiceInclude });
    // Editing quantities/prices of a posted invoice re-posts its ledger entry so
    // revenue, tax and COGS match the new lines.
    if (isPosted && built.lines.length > 0) {
        await (0, accounting_service_1.reverseJournalBySource)(tx, {
            sourceType: 'INVOICE',
            sourceId: invoice.id,
            reversalSourceType: 'INVOICE_EDIT',
            memo: `Invoice ${invoice.number} edited`,
            reference: invoice.number,
            userId: options.userId,
        });
        await postInvoiceJournalTx(tx, updated, options.userId);
    }
    if (updated.customerId)
        await recalcCustomerBalance(tx, updated.customerId);
    if (invoice.customerId && invoice.customerId !== updated.customerId) {
        await recalcCustomerBalance(tx, invoice.customerId);
    }
    return updated;
}
async function updateInvoice(id, input, options = {}) {
    return prisma_1.prisma.$transaction((tx) => updateInvoiceTx(tx, id, input, options));
}
//# sourceMappingURL=invoices.service.js.map