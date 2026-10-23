"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.transferInclude = void 0;
exports.listCashBoxes = listCashBoxes;
exports.getCashBox = getCashBox;
exports.createCashBox = createCashBox;
exports.setCashBoxOpeningBalance = setCashBoxOpeningBalance;
exports.updateCashBox = updateCashBox;
exports.deleteCashBox = deleteCashBox;
exports.inclusiveEnd = inclusiveEnd;
exports.buildCashBoxStatement = buildCashBoxStatement;
exports.createTransfer = createTransfer;
exports.updateTransfer = updateTransfer;
exports.cancelTransfer = cancelTransfer;
exports.listTransfers = listTransfers;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const sequence_1 = require("../../lib/sequence");
const accounting_service_1 = require("../accounting/accounting.service");
const payments_service_1 = require("../payments/payments.service");
exports.transferInclude = {
    fromBox: { select: { id: true, code: true, name: true } },
    toBox: { select: { id: true, code: true, name: true } },
    user: { select: { id: true, name: true } },
};
// ---------------------------------------------------------------------------
// Cash boxes
// ---------------------------------------------------------------------------
/** Lists boxes with their live balances (creates the default box when empty). */
async function listCashBoxes() {
    return prisma_1.prisma.$transaction(async (tx) => {
        await (0, payments_service_1.ensureDefaultCashBoxTx)(tx);
        const boxes = await tx.cashBox.findMany({
            orderBy: [{ type: 'asc' }, { createdAt: 'asc' }],
        });
        const balances = await (0, payments_service_1.cashBoxBalancesTx)(tx, boxes);
        return boxes.map((box) => ({
            ...box,
            openingBalance: (0, money_1.round2)(Number(box.openingBalance)),
            balance: balances.get(box.id) ?? 0,
        }));
    });
}
async function getCashBox(id) {
    const box = await prisma_1.prisma.cashBox.findUnique({ where: { id } });
    if (!box)
        throw api_error_1.ApiError.notFound('Cash box not found', 'BOX_NOT_FOUND');
    const balance = await prisma_1.prisma.$transaction((tx) => (0, payments_service_1.cashBoxBalanceTx)(tx, box));
    return { ...box, openingBalance: (0, money_1.round2)(Number(box.openingBalance)), balance };
}
async function clearOtherDefaults(tx, exceptId) {
    await tx.cashBox.updateMany({
        where: { isDefault: true, ...(exceptId ? { id: { not: exceptId } } : {}) },
        data: { isDefault: false },
    });
}
async function createCashBox(input, userId) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const code = input.code.trim().toUpperCase();
        const existing = await tx.cashBox.findUnique({ where: { code } });
        if (existing)
            throw api_error_1.ApiError.conflict(`A cash box with code "${code}" already exists`, 'DUPLICATE_CODE');
        if (input.isDefault)
            await clearOtherDefaults(tx);
        const opening = (0, money_1.round2)(input.openingBalance ?? 0);
        const box = await tx.cashBox.create({
            data: {
                code,
                name: input.name.trim(),
                type: input.type ?? 'SUB',
                openingBalance: opening,
                active: input.active ?? true,
                isDefault: input.isDefault ?? false,
            },
        });
        // Opening cash is capital: Dr Cash / Cr Owner's Equity.
        if (opening > 0) {
            await (0, accounting_service_1.postJournal)(tx, {
                memo: `Opening balance for cash box ${box.name}`,
                reference: `OB-BOX-${box.code}`,
                sourceType: 'OPENING_CASHBOX',
                sourceId: box.id,
                userId,
                lines: [
                    { accountCode: accounting_service_1.ACCOUNT.CASH, debit: opening, description: 'Opening cash' },
                    { accountCode: accounting_service_1.ACCOUNT.EQUITY, credit: opening, description: 'Opening capital' },
                ],
            });
        }
        return box;
    });
}
/**
 * Changes the opening balance of a cash box and posts the matching capital
 * correction (delta Dr Cash / Cr Equity, or the reverse when reduced).
 */
async function setCashBoxOpeningBalance(id, amount, userId) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const box = await tx.cashBox.findUnique({ where: { id } });
        if (!box)
            throw api_error_1.ApiError.notFound('Cash box not found', 'BOX_NOT_FOUND');
        const previous = (0, money_1.round2)(Number(box.openingBalance));
        const next = (0, money_1.round2)(amount);
        const delta = (0, money_1.round2)(next - previous);
        if (delta !== 0) {
            await (0, accounting_service_1.postJournal)(tx, {
                memo: `Opening balance adjustment for cash box ${box.name}`,
                reference: `OB-BOX-${box.code}`,
                sourceType: 'OPENING_CASHBOX',
                sourceId: box.id,
                userId,
                lines: delta > 0
                    ? [
                        { accountCode: accounting_service_1.ACCOUNT.CASH, debit: delta, description: 'Opening cash increase' },
                        { accountCode: accounting_service_1.ACCOUNT.EQUITY, credit: delta, description: 'Opening capital increase' },
                    ]
                    : [
                        { accountCode: accounting_service_1.ACCOUNT.EQUITY, debit: -delta, description: 'Opening capital decrease' },
                        { accountCode: accounting_service_1.ACCOUNT.CASH, credit: -delta, description: 'Opening cash decrease' },
                    ],
            });
        }
        return tx.cashBox.update({ where: { id }, data: { openingBalance: next } });
    });
}
async function updateCashBox(id, input, userId) {
    // Opening-balance edits are handled by setCashBoxOpeningBalance so the
    // matching capital journal is always posted.
    if (input.openingBalance !== undefined) {
        await setCashBoxOpeningBalance(id, input.openingBalance, userId);
    }
    return prisma_1.prisma.$transaction(async (tx) => {
        const box = await tx.cashBox.findUnique({ where: { id } });
        if (!box)
            throw api_error_1.ApiError.notFound('Cash box not found', 'BOX_NOT_FOUND');
        if (input.code) {
            const code = input.code.trim().toUpperCase();
            const clash = await tx.cashBox.findFirst({ where: { code, id: { not: id } } });
            if (clash)
                throw api_error_1.ApiError.conflict(`A cash box with code "${code}" already exists`, 'DUPLICATE_CODE');
        }
        if (input.isDefault)
            await clearOtherDefaults(tx, id);
        if (input.active === false && box.isDefault) {
            const another = await tx.cashBox.findFirst({
                where: { id: { not: id }, active: true },
                orderBy: { createdAt: 'asc' },
            });
            if (another) {
                await tx.cashBox.update({ where: { id: another.id }, data: { isDefault: true } });
            }
        }
        return tx.cashBox.update({
            where: { id },
            data: {
                ...(input.code !== undefined ? { code: input.code.trim().toUpperCase() } : {}),
                ...(input.name !== undefined ? { name: input.name.trim() } : {}),
                ...(input.type !== undefined ? { type: input.type } : {}),
                ...(input.active !== undefined ? { active: input.active } : {}),
                ...(input.isDefault !== undefined ? { isDefault: input.isDefault } : {}),
            },
        });
    });
}
async function deleteCashBox(id) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const box = await tx.cashBox.findUnique({ where: { id } });
        if (!box)
            throw api_error_1.ApiError.notFound('Cash box not found', 'BOX_NOT_FOUND');
        const [payments, transfers] = await Promise.all([
            tx.payment.count({ where: { cashBoxId: id } }),
            tx.cashTransfer.count({ where: { OR: [{ fromBoxId: id }, { toBoxId: id }] } }),
        ]);
        if (payments + transfers > 0) {
            throw api_error_1.ApiError.conflict('This cash box has movements. Deactivate it instead of deleting it.', 'BOX_HAS_MOVEMENTS');
        }
        await tx.cashBox.delete({ where: { id } });
        if (box.isDefault) {
            const another = await tx.cashBox.findFirst({ orderBy: { createdAt: 'asc' } });
            if (another)
                await tx.cashBox.update({ where: { id: another.id }, data: { isDefault: true } });
        }
        return { id };
    });
}
/** Extends a date-only bound to the last millisecond of that day. */
function inclusiveEnd(date) {
    const clone = new Date(date);
    if (clone.getUTCHours() === 0 &&
        clone.getUTCMinutes() === 0 &&
        clone.getUTCSeconds() === 0 &&
        clone.getUTCMilliseconds() === 0) {
        clone.setUTCHours(23, 59, 59, 999);
    }
    return clone;
}
function rangeFilter(from, to) {
    if (!from && !to)
        return undefined;
    return {
        ...(from ? { gte: from } : {}),
        ...(to ? { lte: inclusiveEnd(to) } : {}),
    };
}
async function buildCashBoxStatement(boxId, from, to) {
    const box = await prisma_1.prisma.cashBox.findUnique({ where: { id: boxId } });
    if (!box)
        throw api_error_1.ApiError.notFound('Cash box not found', 'BOX_NOT_FOUND');
    const period = rangeFilter(from, to);
    const before = from ? { lt: from } : undefined;
    const [payments, transfersOut, transfersIn, expenses, beforeTotals] = await Promise.all([
        prisma_1.prisma.payment.findMany({
            where: {
                cashBoxId: boxId,
                cancelledAt: null,
                ...(period ? { paidAt: period } : {}),
            },
            include: {
                customer: { select: { name: true } },
                supplier: { select: { name: true } },
            },
            orderBy: [{ paidAt: 'asc' }, { createdAt: 'asc' }],
        }),
        prisma_1.prisma.cashTransfer.findMany({
            where: {
                fromBoxId: boxId,
                cancelledAt: null,
                ...(period ? { transferDate: period } : {}),
            },
            include: { toBox: { select: { name: true } } },
            orderBy: [{ transferDate: 'asc' }, { createdAt: 'asc' }],
        }),
        prisma_1.prisma.cashTransfer.findMany({
            where: {
                toBoxId: boxId,
                cancelledAt: null,
                ...(period ? { transferDate: period } : {}),
            },
            include: { fromBox: { select: { name: true } } },
            orderBy: [{ transferDate: 'asc' }, { createdAt: 'asc' }],
        }),
        prisma_1.prisma.expense.findMany({
            where: {
                cashBoxId: boxId,
                cancelledAt: null,
                ...(period ? { spentAt: period } : {}),
            },
            include: { category: { select: { name: true } } },
            orderBy: [{ spentAt: 'asc' }, { createdAt: 'asc' }],
        }),
        before
            ? Promise.all([
                prisma_1.prisma.payment.aggregate({
                    where: { cashBoxId: boxId, direction: 'INBOUND', cancelledAt: null, paidAt: before },
                    _sum: { amount: true },
                }),
                prisma_1.prisma.payment.aggregate({
                    where: { cashBoxId: boxId, direction: 'OUTBOUND', cancelledAt: null, paidAt: before },
                    _sum: { amount: true },
                }),
                prisma_1.prisma.cashTransfer.aggregate({
                    where: { toBoxId: boxId, cancelledAt: null, transferDate: before },
                    _sum: { amount: true },
                }),
                prisma_1.prisma.cashTransfer.aggregate({
                    where: { fromBoxId: boxId, cancelledAt: null, transferDate: before },
                    _sum: { amount: true },
                }),
                prisma_1.prisma.expense.aggregate({
                    where: { cashBoxId: boxId, cancelledAt: null, spentAt: before },
                    _sum: { amount: true },
                }),
            ])
            : null,
    ]);
    let opening = (0, money_1.round2)(Number(box.openingBalance));
    if (beforeTotals) {
        const [pIn, pOut, tIn, tOut, exp] = beforeTotals;
        opening = (0, money_1.round2)(opening +
            Number(pIn._sum.amount ?? 0) -
            Number(pOut._sum.amount ?? 0) +
            Number(tIn._sum.amount ?? 0) -
            Number(tOut._sum.amount ?? 0) -
            Number(exp._sum.amount ?? 0));
    }
    const dated = [];
    for (const payment of payments) {
        const inbound = payment.direction === 'INBOUND';
        const who = payment.customer?.name ?? payment.supplier?.name ?? null;
        const description = [who, payment.note].filter(Boolean).join(' · ') || `Payment ${payment.number}`;
        dated.push({
            when: payment.paidAt,
            createdAt: payment.createdAt,
            kind: 0,
            row: {
                date: payment.paidAt.toISOString(),
                type: inbound ? 'PAYMENT_IN' : 'PAYMENT_OUT',
                direction: inbound ? 'IN' : 'OUT',
                number: payment.number,
                description,
                amount: (0, money_1.round2)(Number(payment.amount)),
                method: payment.method,
                reference: payment.reference,
                paymentId: payment.id,
            },
        });
    }
    for (const transfer of transfersOut) {
        dated.push({
            when: transfer.transferDate,
            createdAt: transfer.createdAt,
            kind: 1,
            row: {
                date: transfer.transferDate.toISOString(),
                type: 'TRANSFER_OUT',
                direction: 'OUT',
                number: transfer.number,
                description: `Transfer to ${transfer.toBox.name}`,
                amount: (0, money_1.round2)(Number(transfer.amount)),
                reference: transfer.reference,
                transferId: transfer.id,
            },
        });
    }
    for (const transfer of transfersIn) {
        dated.push({
            when: transfer.transferDate,
            createdAt: transfer.createdAt,
            kind: 1,
            row: {
                date: transfer.transferDate.toISOString(),
                type: 'TRANSFER_IN',
                direction: 'IN',
                number: transfer.number,
                description: `Transfer from ${transfer.fromBox.name}`,
                amount: (0, money_1.round2)(Number(transfer.amount)),
                reference: transfer.reference,
                transferId: transfer.id,
            },
        });
    }
    for (const expense of expenses) {
        const description = [expense.category?.name, expense.payee, expense.note].filter(Boolean).join(' · ') ||
            `Expense ${expense.number}`;
        dated.push({
            when: expense.spentAt,
            createdAt: expense.createdAt,
            kind: 0,
            row: {
                date: expense.spentAt.toISOString(),
                type: 'EXPENSE',
                direction: 'OUT',
                number: expense.number,
                description,
                amount: (0, money_1.round2)(Number(expense.amount)),
                method: expense.method,
                reference: expense.reference,
                expenseId: expense.id,
            },
        });
    }
    dated.sort((a, b) => a.when.getTime() - b.when.getTime() || a.createdAt.getTime() - b.createdAt.getTime());
    let running = opening;
    let inTotal = 0;
    let outTotal = 0;
    const rows = dated.map((entry) => {
        const signed = entry.row.direction === 'IN' ? entry.row.amount : -entry.row.amount;
        running = (0, money_1.round2)(running + signed);
        if (entry.row.direction === 'IN')
            inTotal = (0, money_1.round2)(inTotal + entry.row.amount);
        else
            outTotal = (0, money_1.round2)(outTotal + entry.row.amount);
        return { ...entry.row, balance: running };
    });
    return {
        box: {
            id: box.id,
            code: box.code,
            name: box.name,
            type: box.type,
            openingBalance: (0, money_1.round2)(Number(box.openingBalance)),
        },
        from: from ? from.toISOString() : null,
        to: to ? to.toISOString() : null,
        openingBalance: opening,
        closingBalance: running,
        inTotal,
        outTotal,
        rows,
    };
}
async function createTransfer(input) {
    return prisma_1.prisma.$transaction(async (tx) => {
        if (input.fromBoxId === input.toBoxId) {
            throw api_error_1.ApiError.badRequest('Source and destination boxes must differ', 'SAME_BOX');
        }
        const amount = (0, money_1.round2)(input.amount);
        if (amount <= 0)
            throw api_error_1.ApiError.badRequest('Transfer amount must be greater than zero');
        const from = await tx.cashBox.findUnique({ where: { id: input.fromBoxId } });
        if (!from)
            throw api_error_1.ApiError.notFound('Source cash box not found', 'BOX_NOT_FOUND');
        const to = await tx.cashBox.findUnique({ where: { id: input.toBoxId } });
        if (!to)
            throw api_error_1.ApiError.notFound('Destination cash box not found', 'BOX_NOT_FOUND');
        if (!from.active)
            throw api_error_1.ApiError.badRequest('Source cash box is inactive', 'BOX_INACTIVE');
        if (!to.active)
            throw api_error_1.ApiError.badRequest('Destination cash box is inactive', 'BOX_INACTIVE');
        const available = await (0, payments_service_1.cashBoxBalanceTx)(tx, from);
        if (amount > available + 0.01) {
            throw api_error_1.ApiError.badRequest(`Insufficient funds in cash box "${from.name}" (available ${available}, requested ${amount})`, 'INSUFFICIENT_FUNDS', { balance: available, attempted: amount, cashBoxId: from.id });
        }
        const transferDate = input.transferDate ?? new Date();
        const number = await (0, sequence_1.nextNumber)(tx, 'transfer', 'TRF', transferDate);
        // Both boxes are cash, so the double entry nets to zero (Dr 1000 / Cr 1000)
        // and no general-ledger entry is needed; the box statement is the ledger.
        return tx.cashTransfer.create({
            data: {
                number,
                fromBoxId: from.id,
                toBoxId: to.id,
                amount,
                exchangeRate: input.exchangeRate ?? 1,
                reference: input.reference ?? null,
                note: input.note ?? null,
                transferDate,
                userId: input.userId ?? null,
            },
            include: exports.transferInclude,
        });
    });
}
async function updateTransfer(id, input) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const transfer = await tx.cashTransfer.findUnique({ where: { id } });
        if (!transfer)
            throw api_error_1.ApiError.notFound('Transfer not found', 'TRANSFER_NOT_FOUND');
        if (transfer.cancelledAt) {
            throw api_error_1.ApiError.conflict('Cancelled transfers cannot be edited', 'CANCELLED_TRANSFER');
        }
        const amount = input.amount !== undefined ? (0, money_1.round2)(input.amount) : (0, money_1.round2)(Number(transfer.amount));
        if (amount <= 0)
            throw api_error_1.ApiError.badRequest('Transfer amount must be greater than zero');
        if (amount > (0, money_1.round2)(Number(transfer.amount))) {
            const from = await tx.cashBox.findUnique({ where: { id: transfer.fromBoxId } });
            if (!from)
                throw api_error_1.ApiError.notFound('Source cash box not found', 'BOX_NOT_FOUND');
            // The current transfer already counts as an outflow; add it back before
            // checking whether the larger amount still fits.
            const available = (0, money_1.round2)((await (0, payments_service_1.cashBoxBalanceTx)(tx, from)) + Number(transfer.amount));
            if (amount > available + 0.01) {
                throw api_error_1.ApiError.badRequest(`Insufficient funds in cash box "${from.name}" (available ${available}, requested ${amount})`, 'INSUFFICIENT_FUNDS', { balance: available, attempted: amount, cashBoxId: from.id });
            }
        }
        return tx.cashTransfer.update({
            where: { id },
            data: {
                amount,
                ...(input.reference !== undefined ? { reference: input.reference } : {}),
                ...(input.note !== undefined ? { note: input.note } : {}),
                ...(input.transferDate !== undefined && input.transferDate !== null
                    ? { transferDate: input.transferDate }
                    : {}),
            },
            include: exports.transferInclude,
        });
    });
}
async function cancelTransfer(id, userId) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const transfer = await tx.cashTransfer.findUnique({ where: { id } });
        if (!transfer)
            throw api_error_1.ApiError.notFound('Transfer not found', 'TRANSFER_NOT_FOUND');
        if (transfer.cancelledAt)
            throw api_error_1.ApiError.conflict('This transfer is already cancelled', 'ALREADY_CANCELLED');
        return tx.cashTransfer.update({
            where: { id },
            data: { cancelledAt: new Date(), cancelledBy: userId ?? null },
            include: exports.transferInclude,
        });
    });
}
async function listTransfers(filter) {
    const period = rangeFilter(filter.from, filter.to);
    const where = {
        ...(filter.boxId ? { OR: [{ fromBoxId: filter.boxId }, { toBoxId: filter.boxId }] } : {}),
        ...(period ? { transferDate: period } : {}),
        ...(filter.paged && !filter.includeCancelled ? { cancelledAt: null } : {}),
    };
    if (filter.paged) {
        const [items, total] = await Promise.all([
            prisma_1.prisma.cashTransfer.findMany({
                where,
                include: exports.transferInclude,
                orderBy: [{ transferDate: 'desc' }, { createdAt: 'desc' }],
                take: filter.limit ?? 25,
                skip: filter.skip ?? 0,
            }),
            prisma_1.prisma.cashTransfer.count({ where }),
        ]);
        return { items, total };
    }
    return prisma_1.prisma.cashTransfer.findMany({
        where,
        include: exports.transferInclude,
        orderBy: [{ transferDate: 'desc' }, { createdAt: 'desc' }],
        take: filter.limit ?? 100,
    });
}
//# sourceMappingURL=treasury.service.js.map