"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildCustomerStatement = buildCustomerStatement;
exports.buildSupplierStatement = buildSupplierStatement;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const isoDay = (value) => value ? value.toISOString().slice(0, 10) : null;
/** Chronological order, ties broken by creation time, documents before payments. */
function compareRawRows(a, b) {
    const byDate = a.date.getTime() - b.date.getTime();
    if (byDate !== 0)
        return byDate;
    const byCreated = a.createdAt.getTime() - b.createdAt.getTime();
    if (byCreated !== 0)
        return byCreated;
    return a.kind - b.kind;
}
function buildRows(openingBalance, raw, delta) {
    raw.sort(compareRawRows);
    let running = (0, money_1.round2)(openingBalance);
    let debitTotal = 0;
    let creditTotal = 0;
    const rows = raw.map((row) => {
        running = (0, money_1.round2)(running + delta(row));
        debitTotal = (0, money_1.round2)(debitTotal + row.debit);
        creditTotal = (0, money_1.round2)(creditTotal + row.credit);
        return {
            date: row.date.toISOString(),
            type: row.type,
            number: row.number,
            description: row.description,
            debit: row.debit,
            credit: row.credit,
            balance: running,
        };
    });
    return { rows, totals: { debit: debitTotal, credit: creditTotal, closingBalance: running } };
}
function paymentDescription(payment) {
    const parts = [`Payment ${payment.number}`, payment.method];
    if (payment.reference)
        parts.push(payment.reference);
    return parts.join(' · ');
}
/**
 * Builds a customer account statement. Invoices are debits (the customer owes
 * us), inbound payments are credits and outbound payments (refunds) are debits.
 */
async function buildCustomerStatement(customerId, from, to) {
    const customer = await prisma_1.prisma.customer.findUnique({ where: { id: customerId } });
    if (!customer)
        throw api_error_1.ApiError.notFound('Customer not found');
    const range = from || to ? { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) } : undefined;
    const [invoices, payments] = await Promise.all([
        prisma_1.prisma.invoice.findMany({
            where: {
                customerId,
                status: { not: 'VOID' },
                ...(range ? { issueDate: range } : {}),
            },
            select: { id: true, number: true, total: true, issueDate: true, notes: true, createdAt: true },
        }),
        prisma_1.prisma.payment.findMany({
            where: { customerId, cancelledAt: null, ...(range ? { paidAt: range } : {}) },
            select: {
                id: true,
                number: true,
                amount: true,
                direction: true,
                method: true,
                reference: true,
                paidAt: true,
                createdAt: true,
            },
        }),
    ]);
    let openingBalance = 0;
    if (from) {
        const [invoiceSum, inboundSum, outboundSum] = await Promise.all([
            prisma_1.prisma.invoice.aggregate({
                where: { customerId, status: { not: 'VOID' }, issueDate: { lt: from } },
                _sum: { total: true },
            }),
            prisma_1.prisma.payment.aggregate({
                where: { customerId, direction: 'INBOUND', cancelledAt: null, paidAt: { lt: from } },
                _sum: { amount: true },
            }),
            prisma_1.prisma.payment.aggregate({
                where: { customerId, direction: 'OUTBOUND', cancelledAt: null, paidAt: { lt: from } },
                _sum: { amount: true },
            }),
        ]);
        openingBalance = (0, money_1.round2)(Number(invoiceSum._sum.total ?? 0) -
            Number(inboundSum._sum.amount ?? 0) +
            Number(outboundSum._sum.amount ?? 0));
    }
    // The customer's stored balance also carries the opening balance that was
    // entered when the customer was created (posted to the ledger, but with no
    // invoice or payment behind it). Reconcile the statement to that figure so the
    // opening balance shows up here too.
    const [allInvoiceSum, allInboundSum, allOutboundSum] = await Promise.all([
        prisma_1.prisma.invoice.aggregate({
            where: { customerId, status: { not: 'VOID' } },
            _sum: { total: true },
        }),
        prisma_1.prisma.payment.aggregate({
            where: { customerId, direction: 'INBOUND', cancelledAt: null },
            _sum: { amount: true },
        }),
        prisma_1.prisma.payment.aggregate({
            where: { customerId, direction: 'OUTBOUND', cancelledAt: null },
            _sum: { amount: true },
        }),
    ]);
    const ledgerOpeningBalance = (0, money_1.round2)(Number(customer.balance) -
        Number(allInvoiceSum._sum.total ?? 0) +
        Number(allInboundSum._sum.amount ?? 0) -
        Number(allOutboundSum._sum.amount ?? 0));
    openingBalance = (0, money_1.round2)(openingBalance + ledgerOpeningBalance);
    const raw = [];
    for (const invoice of invoices) {
        const note = invoice.notes?.trim();
        raw.push({
            date: invoice.issueDate,
            createdAt: invoice.createdAt,
            kind: 0,
            type: 'INVOICE',
            number: invoice.number,
            description: note && note.length > 0 ? note : `Invoice ${invoice.number}`,
            debit: (0, money_1.round2)(Number(invoice.total)),
            credit: 0,
        });
    }
    for (const payment of payments) {
        const inbound = payment.direction === 'INBOUND';
        const amount = (0, money_1.round2)(Number(payment.amount));
        raw.push({
            date: payment.paidAt,
            createdAt: payment.createdAt,
            kind: 1,
            type: 'PAYMENT',
            number: payment.number,
            description: paymentDescription(payment),
            debit: inbound ? 0 : amount,
            credit: inbound ? amount : 0,
        });
    }
    const { rows, totals } = buildRows(openingBalance, raw, (row) => row.debit - row.credit);
    return {
        customer: {
            id: customer.id,
            name: customer.name,
            email: customer.email,
            phone: customer.phone,
            address: customer.address,
            balance: Number(customer.balance),
            creditLimit: Number(customer.creditLimit),
        },
        from: isoDay(from),
        to: isoDay(to),
        openingBalance,
        rows,
        totals,
    };
}
/**
 * Builds a supplier account statement. Purchase orders are credits (we owe the
 * supplier), outbound payments are debits. A positive balance means we owe the
 * supplier.
 */
async function buildSupplierStatement(supplierId, from, to) {
    const supplier = await prisma_1.prisma.supplier.findUnique({ where: { id: supplierId } });
    if (!supplier)
        throw api_error_1.ApiError.notFound('Supplier not found');
    const range = from || to ? { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) } : undefined;
    const [orders, payments] = await Promise.all([
        prisma_1.prisma.purchaseOrder.findMany({
            where: {
                supplierId,
                status: { not: 'CANCELLED' },
                ...(range ? { orderDate: range } : {}),
            },
            select: { id: true, number: true, total: true, orderDate: true, notes: true, createdAt: true },
        }),
        prisma_1.prisma.payment.findMany({
            where: { supplierId, direction: 'OUTBOUND', cancelledAt: null, ...(range ? { paidAt: range } : {}) },
            select: {
                id: true,
                number: true,
                amount: true,
                method: true,
                reference: true,
                paidAt: true,
                createdAt: true,
            },
        }),
    ]);
    let openingBalance = 0;
    if (from) {
        const [orderSum, paymentSum] = await Promise.all([
            prisma_1.prisma.purchaseOrder.aggregate({
                where: { supplierId, status: { not: 'CANCELLED' }, orderDate: { lt: from } },
                _sum: { total: true },
            }),
            prisma_1.prisma.payment.aggregate({
                where: { supplierId, direction: 'OUTBOUND', cancelledAt: null, paidAt: { lt: from } },
                _sum: { amount: true },
            }),
        ]);
        openingBalance = (0, money_1.round2)(Number(orderSum._sum.total ?? 0) - Number(paymentSum._sum.amount ?? 0));
    }
    // Include the supplier's opening balance (entered at creation and posted to
    // the ledger without a purchase order behind it) so it shows on the statement.
    const [allOrderSum, allPaymentSum] = await Promise.all([
        prisma_1.prisma.purchaseOrder.aggregate({
            where: { supplierId, status: { not: 'CANCELLED' } },
            _sum: { total: true },
        }),
        prisma_1.prisma.payment.aggregate({
            where: { supplierId, direction: 'OUTBOUND', cancelledAt: null },
            _sum: { amount: true },
        }),
    ]);
    const ledgerOpeningBalance = (0, money_1.round2)(Number(supplier.balance) -
        Number(allOrderSum._sum.total ?? 0) +
        Number(allPaymentSum._sum.amount ?? 0));
    openingBalance = (0, money_1.round2)(openingBalance + ledgerOpeningBalance);
    const raw = [];
    for (const order of orders) {
        const note = order.notes?.trim();
        raw.push({
            date: order.orderDate,
            createdAt: order.createdAt,
            kind: 0,
            type: 'PURCHASE_ORDER',
            number: order.number,
            description: note && note.length > 0 ? note : `Purchase order ${order.number}`,
            debit: 0,
            credit: (0, money_1.round2)(Number(order.total)),
        });
    }
    for (const payment of payments) {
        raw.push({
            date: payment.paidAt,
            createdAt: payment.createdAt,
            kind: 1,
            type: 'PAYMENT',
            number: payment.number,
            description: paymentDescription(payment),
            debit: (0, money_1.round2)(Number(payment.amount)),
            credit: 0,
        });
    }
    const { rows, totals } = buildRows(openingBalance, raw, (row) => row.credit - row.debit);
    return {
        supplier: {
            id: supplier.id,
            name: supplier.name,
            contact: supplier.contact,
            email: supplier.email,
            phone: supplier.phone,
            address: supplier.address,
            balance: Number(supplier.balance),
            paymentTermDays: supplier.paymentTermDays,
        },
        from: isoDay(from),
        to: isoDay(to),
        openingBalance,
        rows,
        totals,
    };
}
//# sourceMappingURL=statement.service.js.map