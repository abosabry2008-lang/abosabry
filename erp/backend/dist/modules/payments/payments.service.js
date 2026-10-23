"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.collectionInclude = exports.paymentInclude = void 0;
exports.ensureDefaultCashBoxTx = ensureDefaultCashBoxTx;
exports.resolveCashBoxTx = resolveCashBoxTx;
exports.cashBoxBalanceTx = cashBoxBalanceTx;
exports.cashBoxBalancesTx = cashBoxBalancesTx;
exports.createPaymentTx = createPaymentTx;
exports.createPayment = createPayment;
exports.cancelPaymentTx = cancelPaymentTx;
exports.cancelPayment = cancelPayment;
exports.updatePaymentTx = updatePaymentTx;
exports.updatePayment = updatePayment;
exports.createCollectionTx = createCollectionTx;
exports.createCollection = createCollection;
exports.cancelCollectionTx = cancelCollectionTx;
exports.cancelCollection = cancelCollection;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const sequence_1 = require("../../lib/sequence");
const settings_1 = require("../../lib/settings");
const accounting_service_1 = require("../accounting/accounting.service");
const invoices_service_1 = require("../invoices/invoices.service");
exports.paymentInclude = {
    customer: { select: { id: true, name: true } },
    supplier: { select: { id: true, name: true } },
    invoice: { select: { id: true, number: true, total: true, balance: true, status: true } },
    currency: { select: { id: true, code: true, symbol: true } },
    user: { select: { id: true, name: true } },
    cashBox: { select: { id: true, code: true, name: true } },
    collectionVoucher: { select: { id: true, number: true } },
};
// ---------------------------------------------------------------------------
// Cash boxes
// ---------------------------------------------------------------------------
/**
 * Returns the default cash box, creating a "main box" the first time the
 * treasury is used so payment forms always have somewhere to post to.
 */
async function ensureDefaultCashBoxTx(tx) {
    const existing = (await tx.cashBox.findFirst({ where: { isDefault: true, active: true }, orderBy: { createdAt: 'asc' } })) ??
        (await tx.cashBox.findFirst({ where: { type: 'MAIN' }, orderBy: { createdAt: 'asc' } })) ??
        (await tx.cashBox.findFirst({ orderBy: { createdAt: 'asc' } }));
    if (existing) {
        // Payments recorded before the treasury existed have no box: attach them
        // to the default box so historical cash movements appear in its balance.
        await tx.payment.updateMany({
            where: { cashBoxId: null },
            data: { cashBoxId: existing.id },
        });
        return existing;
    }
    const created = await tx.cashBox.upsert({
        where: { code: 'MAIN' },
        create: {
            code: 'MAIN',
            name: 'الخزنة الرئيسية',
            type: 'MAIN',
            isDefault: true,
        },
        update: {},
    });
    await tx.payment.updateMany({
        where: { cashBoxId: null },
        data: { cashBoxId: created.id },
    });
    return created;
}
/** Resolves the requested box (or the default one) and validates it is active. */
async function resolveCashBoxTx(tx, cashBoxId) {
    if (!cashBoxId)
        return ensureDefaultCashBoxTx(tx);
    const box = await tx.cashBox.findUnique({ where: { id: cashBoxId } });
    if (!box)
        throw api_error_1.ApiError.notFound('Cash box not found', 'BOX_NOT_FOUND');
    if (!box.active)
        throw api_error_1.ApiError.badRequest('This cash box is inactive', 'BOX_INACTIVE');
    return box;
}
/**
 * Current balance of a box: its opening balance plus every live (non
 * cancelled) payment and transfer that touches it. Computing on read keeps the
 * figure correct even after an admin edits or cancels a movement.
 */
async function cashBoxBalanceTx(tx, box) {
    const [paymentsIn, paymentsOut, transfersIn, transfersOut, expenses] = await Promise.all([
        tx.payment.aggregate({
            where: { cashBoxId: box.id, direction: 'INBOUND', cancelledAt: null },
            _sum: { amount: true },
        }),
        tx.payment.aggregate({
            where: { cashBoxId: box.id, direction: 'OUTBOUND', cancelledAt: null },
            _sum: { amount: true },
        }),
        tx.cashTransfer.aggregate({
            where: { toBoxId: box.id, cancelledAt: null },
            _sum: { amount: true },
        }),
        tx.cashTransfer.aggregate({
            where: { fromBoxId: box.id, cancelledAt: null },
            _sum: { amount: true },
        }),
        tx.expense.aggregate({
            where: { cashBoxId: box.id, cancelledAt: null },
            _sum: { amount: true },
        }),
    ]);
    return (0, money_1.round2)(Number(box.openingBalance) +
        Number(paymentsIn._sum.amount ?? 0) -
        Number(paymentsOut._sum.amount ?? 0) +
        Number(transfersIn._sum.amount ?? 0) -
        Number(transfersOut._sum.amount ?? 0) -
        Number(expenses._sum.amount ?? 0));
}
/** Balances for many boxes with aggregate queries (used by the list screen). */
async function cashBoxBalancesTx(tx, boxes) {
    const balances = new Map();
    if (boxes.length === 0)
        return balances;
    const ids = boxes.map((box) => box.id);
    const [payments, transfersIn, transfersOut, expenses] = await Promise.all([
        tx.payment.groupBy({
            by: ['cashBoxId', 'direction'],
            where: { cashBoxId: { in: ids }, cancelledAt: null },
            _sum: { amount: true },
        }),
        tx.cashTransfer.groupBy({
            by: ['toBoxId'],
            where: { toBoxId: { in: ids }, cancelledAt: null },
            _sum: { amount: true },
        }),
        tx.cashTransfer.groupBy({
            by: ['fromBoxId'],
            where: { fromBoxId: { in: ids }, cancelledAt: null },
            _sum: { amount: true },
        }),
        tx.expense.groupBy({
            by: ['cashBoxId'],
            where: { cashBoxId: { in: ids }, cancelledAt: null },
            _sum: { amount: true },
        }),
    ]);
    for (const box of boxes)
        balances.set(box.id, (0, money_1.round2)(Number(box.openingBalance)));
    for (const row of payments) {
        if (!row.cashBoxId)
            continue;
        const current = balances.get(row.cashBoxId) ?? 0;
        const amount = Number(row._sum.amount ?? 0);
        balances.set(row.cashBoxId, (0, money_1.round2)(current + (row.direction === 'INBOUND' ? amount : -amount)));
    }
    for (const row of transfersIn) {
        const current = balances.get(row.toBoxId) ?? 0;
        balances.set(row.toBoxId, (0, money_1.round2)(current + Number(row._sum.amount ?? 0)));
    }
    for (const row of transfersOut) {
        const current = balances.get(row.fromBoxId) ?? 0;
        balances.set(row.fromBoxId, (0, money_1.round2)(current - Number(row._sum.amount ?? 0)));
    }
    for (const row of expenses) {
        if (!row.cashBoxId)
            continue;
        const current = balances.get(row.cashBoxId) ?? 0;
        balances.set(row.cashBoxId, (0, money_1.round2)(current - Number(row._sum.amount ?? 0)));
    }
    return balances;
}
// ---------------------------------------------------------------------------
// Journal posting
// ---------------------------------------------------------------------------
async function postPaymentJournalTx(tx, input) {
    const cashAccount = input.method === 'CASH' ? accounting_service_1.ACCOUNT.CASH : accounting_service_1.ACCOUNT.BANK;
    await (0, accounting_service_1.postJournal)(tx, {
        memo: input.memo ?? `Payment ${input.number}`,
        reference: input.number,
        sourceType: 'PAYMENT',
        sourceId: input.paymentId,
        userId: input.userId,
        entryDate: input.paidAt,
        lines: input.direction === 'INBOUND'
            ? [
                { accountCode: cashAccount, debit: input.amount, description: `Funds received (${input.number})` },
                {
                    accountCode: accounting_service_1.ACCOUNT.RECEIVABLE,
                    credit: input.amount,
                    description: `Receipt (${input.number})`,
                },
            ]
            : [
                { accountCode: accounting_service_1.ACCOUNT.PAYABLE, debit: input.amount, description: `Payable settled (${input.number})` },
                { accountCode: cashAccount, credit: input.amount, description: `Funds paid (${input.number})` },
            ],
    });
}
// ---------------------------------------------------------------------------
// Creating payments
// ---------------------------------------------------------------------------
async function createPaymentTx(tx, input) {
    if (input.amount <= 0)
        throw api_error_1.ApiError.badRequest('Payment amount must be greater than zero');
    const method = input.method ?? 'CASH';
    const direction = input.direction ?? 'INBOUND';
    const paidAt = input.paidAt ?? new Date();
    const amount = (0, money_1.round2)(input.amount);
    const settings = await (0, settings_1.getSettings)(tx);
    const number = await (0, sequence_1.nextNumber)(tx, 'payment', settings.paymentPrefix, paidAt);
    const box = await resolveCashBoxTx(tx, input.cashBoxId);
    if (input.invoiceId) {
        const invoice = await tx.invoice.findUnique({ where: { id: input.invoiceId } });
        if (!invoice)
            throw api_error_1.ApiError.notFound('Invoice not found');
        if (invoice.status === 'VOID' || invoice.status === 'DRAFT') {
            throw api_error_1.ApiError.badRequest('Only issued invoices can receive payments', 'NOT_PAYABLE');
        }
        const balance = (0, money_1.round2)(Number(invoice.balance));
        if (amount > balance + 0.01) {
            throw api_error_1.ApiError.badRequest(`Payment exceeds the outstanding balance of ${balance}`, 'OVERPAYMENT', {
                balance,
                attempted: amount,
            });
        }
        const amountPaid = (0, money_1.round2)(Number(invoice.amountPaid) + amount);
        const newBalance = (0, money_1.round2)(Math.max(0, balance - amount));
        await tx.invoice.update({
            where: { id: invoice.id },
            data: {
                amountPaid,
                balance: newBalance,
                status: newBalance <= 0.01 ? 'PAID' : 'PARTIALLY_PAID',
            },
        });
        const payment = await tx.payment.create({
            data: {
                number,
                direction: 'INBOUND',
                customerId: invoice.customerId,
                invoiceId: invoice.id,
                currencyId: input.currencyId ?? invoice.currencyId,
                cashBoxId: box.id,
                collectionVoucherId: input.collectionVoucherId ?? null,
                method,
                amount,
                reference: input.reference ?? null,
                note: input.note ?? null,
                paidAt,
                userId: input.userId ?? null,
            },
            include: exports.paymentInclude,
        });
        await postPaymentJournalTx(tx, {
            paymentId: payment.id,
            number,
            direction: 'INBOUND',
            method,
            amount,
            paidAt,
            userId: input.userId,
            memo: `Payment ${number} for invoice ${invoice.number}`,
        });
        if (invoice.customerId)
            await (0, invoices_service_1.recalcCustomerBalance)(tx, invoice.customerId);
        return payment;
    }
    // Outbound money must actually exist in the box it is paid from.
    if (direction === 'OUTBOUND') {
        const available = await cashBoxBalanceTx(tx, box);
        if (amount > available + 0.01) {
            throw api_error_1.ApiError.badRequest(`Insufficient funds in cash box "${box.name}" (available ${available}, requested ${amount})`, 'INSUFFICIENT_FUNDS', { balance: available, attempted: amount, cashBoxId: box.id });
        }
    }
    if (input.supplierId && direction === 'OUTBOUND') {
        const payment = await tx.payment.create({
            data: {
                number,
                direction: 'OUTBOUND',
                supplierId: input.supplierId,
                currencyId: input.currencyId ?? null,
                cashBoxId: box.id,
                collectionVoucherId: input.collectionVoucherId ?? null,
                method,
                amount,
                reference: input.reference ?? null,
                note: input.note ?? null,
                paidAt,
                userId: input.userId ?? null,
            },
            include: exports.paymentInclude,
        });
        await tx.supplier.update({
            where: { id: input.supplierId },
            data: { balance: { decrement: amount } },
        });
        await postPaymentJournalTx(tx, {
            paymentId: payment.id,
            number,
            direction: 'OUTBOUND',
            method,
            amount,
            paidAt,
            userId: input.userId,
            memo: `Supplier payment ${number}`,
        });
        return payment;
    }
    // Unapplied payment (e.g. customer advance / on-account).
    const payment = await tx.payment.create({
        data: {
            number,
            direction,
            customerId: input.customerId ?? null,
            supplierId: input.supplierId ?? null,
            currencyId: input.currencyId ?? null,
            cashBoxId: box.id,
            collectionVoucherId: input.collectionVoucherId ?? null,
            method,
            amount,
            reference: input.reference ?? null,
            note: input.note ?? null,
            paidAt,
            userId: input.userId ?? null,
        },
        include: exports.paymentInclude,
    });
    await postPaymentJournalTx(tx, {
        paymentId: payment.id,
        number,
        direction,
        method,
        amount,
        paidAt,
        userId: input.userId,
    });
    return payment;
}
async function createPayment(input) {
    return prisma_1.prisma.$transaction((tx) => createPaymentTx(tx, input));
}
// ---------------------------------------------------------------------------
// Cancelling / editing payments
// ---------------------------------------------------------------------------
/** Recomputes an invoice's paid amount, balance and status from its live payments. */
async function syncInvoicePaidTx(tx, invoiceId) {
    const invoice = await tx.invoice.findUnique({ where: { id: invoiceId } });
    if (!invoice || invoice.status === 'VOID')
        return;
    const paid = await tx.payment.aggregate({
        where: { invoiceId, cancelledAt: null, direction: 'INBOUND' },
        _sum: { amount: true },
    });
    const amountPaid = (0, money_1.round2)(Number(paid._sum.amount ?? 0));
    const balance = (0, money_1.round2)(Math.max(0, Number(invoice.total) - amountPaid));
    const status = balance <= 0.01 ? 'PAID' : amountPaid > 0 ? 'PARTIALLY_PAID' : 'ISSUED';
    await tx.invoice.update({ where: { id: invoiceId }, data: { amountPaid, balance, status } });
    if (invoice.customerId)
        await (0, invoices_service_1.recalcCustomerBalance)(tx, invoice.customerId);
}
/**
 * Cancels a payment: reverses its journal entry, marks it cancelled (which
 * removes it from box balances and statements) and restores the invoice and
 * supplier balances it had changed.
 */
async function cancelPaymentTx(tx, paymentId, userId) {
    const payment = await tx.payment.findUnique({ where: { id: paymentId } });
    if (!payment)
        throw api_error_1.ApiError.notFound('Payment not found');
    if (payment.cancelledAt)
        throw api_error_1.ApiError.conflict('This payment is already cancelled', 'ALREADY_CANCELLED');
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
    if (payment.invoiceId)
        await syncInvoicePaidTx(tx, payment.invoiceId);
    if (payment.supplierId && payment.direction === 'OUTBOUND' && !payment.invoiceId) {
        await tx.supplier.update({
            where: { id: payment.supplierId },
            data: { balance: { increment: (0, money_1.round2)(Number(payment.amount)) } },
        });
    }
    return tx.payment.findUniqueOrThrow({ where: { id: payment.id }, include: exports.paymentInclude });
}
/** Cancels a standalone payment (collection receipt lines are cancelled through their receipt). */
async function cancelPayment(paymentId, userId) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const payment = await tx.payment.findUnique({ where: { id: paymentId } });
        if (!payment)
            throw api_error_1.ApiError.notFound('Payment not found');
        if (payment.collectionVoucherId) {
            throw api_error_1.ApiError.badRequest('This payment belongs to a collection receipt — cancel the receipt instead', 'COLLECTION_PAYMENT');
        }
        return cancelPaymentTx(tx, paymentId, userId);
    });
}
async function updatePaymentTx(tx, paymentId, input, userId) {
    const payment = await tx.payment.findUnique({ where: { id: paymentId }, include: { invoice: true } });
    if (!payment)
        throw api_error_1.ApiError.notFound('Payment not found');
    if (payment.cancelledAt)
        throw api_error_1.ApiError.conflict('Cancelled payments cannot be edited', 'CANCELLED_PAYMENT');
    if (payment.collectionVoucherId) {
        throw api_error_1.ApiError.badRequest('This payment belongs to a collection receipt — cancel the receipt and record a new one', 'COLLECTION_PAYMENT');
    }
    const oldAmount = (0, money_1.round2)(Number(payment.amount));
    const amount = input.amount !== undefined ? (0, money_1.round2)(input.amount) : oldAmount;
    if (amount <= 0)
        throw api_error_1.ApiError.badRequest('Payment amount must be greater than zero');
    if (payment.invoiceId && amount !== oldAmount) {
        const invoice = payment.invoice;
        if (!invoice)
            throw api_error_1.ApiError.notFound('Invoice not found');
        const others = await tx.payment.aggregate({
            where: { invoiceId: payment.invoiceId, cancelledAt: null, id: { not: payment.id } },
            _sum: { amount: true },
        });
        const maxAmount = (0, money_1.round2)(Number(invoice.total) - Number(others._sum.amount ?? 0));
        if (amount > maxAmount + 0.01) {
            throw api_error_1.ApiError.badRequest(`Payment exceeds the outstanding balance of ${maxAmount}`, 'OVERPAYMENT', {
                balance: maxAmount,
                attempted: amount,
            });
        }
    }
    const targetBox = input.cashBoxId !== undefined
        ? await resolveCashBoxTx(tx, input.cashBoxId)
        : payment.cashBoxId
            ? await tx.cashBox.findUnique({ where: { id: payment.cashBoxId } })
            : null;
    if (payment.direction === 'OUTBOUND' && targetBox) {
        const sameBox = payment.cashBoxId === targetBox.id;
        const available = (0, money_1.round2)((await cashBoxBalanceTx(tx, targetBox)) + (sameBox ? oldAmount : 0));
        if (amount > available + 0.01) {
            throw api_error_1.ApiError.badRequest(`Insufficient funds in cash box "${targetBox.name}" (available ${available}, requested ${amount})`, 'INSUFFICIENT_FUNDS', { balance: available, attempted: amount, cashBoxId: targetBox.id });
        }
    }
    const paidAt = input.paidAt ?? payment.paidAt;
    const dateChanged = paidAt.getTime() !== payment.paidAt.getTime();
    if (amount !== oldAmount || dateChanged) {
        await (0, accounting_service_1.reverseJournalBySource)(tx, {
            sourceType: 'PAYMENT',
            sourceId: payment.id,
            reversalSourceType: 'PAYMENT_EDIT',
            memo: `Payment ${payment.number} edited`,
            reference: payment.number,
            userId,
        });
        await postPaymentJournalTx(tx, {
            paymentId: payment.id,
            number: payment.number,
            direction: payment.direction,
            method: payment.method,
            amount,
            paidAt,
            userId,
            memo: `Payment ${payment.number} (edited)`,
        });
    }
    const updated = await tx.payment.update({
        where: { id: payment.id },
        data: {
            amount,
            paidAt,
            ...(targetBox ? { cashBoxId: targetBox.id } : {}),
            ...(input.note !== undefined ? { note: input.note } : {}),
            ...(input.reference !== undefined ? { reference: input.reference } : {}),
        },
        include: exports.paymentInclude,
    });
    if (payment.invoiceId)
        await syncInvoicePaidTx(tx, payment.invoiceId);
    if (amount !== oldAmount &&
        payment.supplierId &&
        payment.direction === 'OUTBOUND' &&
        !payment.invoiceId) {
        await tx.supplier.update({
            where: { id: payment.supplierId },
            data: { balance: { decrement: (0, money_1.round2)(amount - oldAmount) } },
        });
    }
    return updated;
}
async function updatePayment(paymentId, input, userId) {
    return prisma_1.prisma.$transaction((tx) => updatePaymentTx(tx, paymentId, input, userId));
}
// ---------------------------------------------------------------------------
// Agent collection receipts (multiple customers / invoices in one voucher)
// ---------------------------------------------------------------------------
exports.collectionInclude = {
    cashBox: { select: { id: true, code: true, name: true } },
    salesperson: { select: { id: true, name: true } },
    user: { select: { id: true, name: true } },
    lines: {
        include: {
            customer: { select: { id: true, name: true } },
            cashBox: { select: { id: true, code: true, name: true } },
            invoice: { select: { id: true, number: true, total: true, balance: true, status: true } },
        },
    },
    payments: {
        select: {
            id: true,
            number: true,
            amount: true,
            customerId: true,
            invoiceId: true,
            cancelledAt: true,
        },
    },
};
async function createCollectionTx(tx, input) {
    if (!input.lines || input.lines.length === 0) {
        throw api_error_1.ApiError.badRequest('A collection receipt needs at least one line', 'NO_LINES');
    }
    if (input.lines.some((line) => !(line.amount > 0))) {
        throw api_error_1.ApiError.badRequest('Every collection line needs a positive amount', 'INVALID_LINE');
    }
    const box = await resolveCashBoxTx(tx, input.cashBoxId);
    const collectedAt = input.collectedAt ?? new Date();
    if (input.salespersonId) {
        const salesperson = await tx.user.findUnique({ where: { id: input.salespersonId } });
        if (!salesperson)
            throw api_error_1.ApiError.badRequest('Salesperson not found', 'SALESPERSON_NOT_FOUND');
    }
    const number = await (0, sequence_1.nextNumber)(tx, 'collection', 'COL', collectedAt);
    const voucher = await tx.collectionVoucher.create({
        data: {
            number,
            cashBoxId: box.id,
            salespersonId: input.salespersonId ?? null,
            collectedAt,
            reference: input.reference ?? null,
            note: input.note ?? null,
            userId: input.userId ?? null,
            total: 0,
        },
    });
    let total = 0;
    for (const line of input.lines) {
        let invoice = null;
        if (line.invoiceId) {
            invoice = await tx.invoice.findUnique({
                where: { id: line.invoiceId },
                select: { id: true, number: true, customerId: true },
            });
            if (!invoice)
                throw api_error_1.ApiError.notFound('Invoice not found');
        }
        if (line.customerId && invoice?.customerId && invoice.customerId !== line.customerId) {
            throw api_error_1.ApiError.badRequest('The invoice belongs to a different customer', 'CUSTOMER_MISMATCH');
        }
        const customerId = line.customerId ?? invoice?.customerId ?? null;
        if (!customerId) {
            throw api_error_1.ApiError.badRequest('Each collection line needs a customer', 'CUSTOMER_REQUIRED');
        }
        const amount = (0, money_1.round2)(line.amount);
        const lineBox = line.cashBoxId ? await resolveCashBoxTx(tx, line.cashBoxId) : box;
        await createPaymentTx(tx, {
            invoiceId: invoice?.id ?? null,
            customerId,
            amount,
            direction: 'INBOUND',
            method: 'CASH',
            paidAt: collectedAt,
            reference: input.reference ?? number,
            note: line.note ?? input.note ?? `Collection ${number}`,
            userId: input.userId,
            cashBoxId: lineBox.id,
            collectionVoucherId: voucher.id,
        });
        await tx.collectionLine.create({
            data: {
                collectionVoucherId: voucher.id,
                customerId,
                invoiceId: invoice?.id ?? null,
                cashBoxId: lineBox.id,
                amount,
                note: line.note ?? null,
            },
        });
        total = (0, money_1.round2)(total + amount);
    }
    return tx.collectionVoucher.update({
        where: { id: voucher.id },
        data: { total },
        include: exports.collectionInclude,
    });
}
async function createCollection(input) {
    return prisma_1.prisma.$transaction((tx) => createCollectionTx(tx, input));
}
async function cancelCollectionTx(tx, voucherId, userId) {
    const voucher = await tx.collectionVoucher.findUnique({
        where: { id: voucherId },
        include: { payments: { select: { id: true, cancelledAt: true } } },
    });
    if (!voucher)
        throw api_error_1.ApiError.notFound('Collection receipt not found');
    if (voucher.cancelledAt)
        throw api_error_1.ApiError.conflict('This receipt is already cancelled', 'ALREADY_CANCELLED');
    for (const payment of voucher.payments) {
        if (!payment.cancelledAt)
            await cancelPaymentTx(tx, payment.id, userId);
    }
    return tx.collectionVoucher.update({
        where: { id: voucher.id },
        data: { cancelledAt: new Date(), cancelledBy: userId ?? null },
        include: exports.collectionInclude,
    });
}
async function cancelCollection(voucherId, userId) {
    return prisma_1.prisma.$transaction((tx) => cancelCollectionTx(tx, voucherId, userId));
}
//# sourceMappingURL=payments.service.js.map