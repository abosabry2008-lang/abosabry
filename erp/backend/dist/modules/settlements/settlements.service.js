"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.settlementInclude = void 0;
exports.createSettlement = createSettlement;
exports.updateSettlement = updateSettlement;
exports.cancelSettlement = cancelSettlement;
exports.listSettlements = listSettlements;
exports.getSettlement = getSettlement;
exports.buildSettlementStatement = buildSettlementStatement;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const sequence_1 = require("../../lib/sequence");
const settings_1 = require("../../lib/settings");
const accounting_service_1 = require("../accounting/accounting.service");
const invoices_service_1 = require("../invoices/invoices.service");
// ---------------------------------------------------------------------------
// Account settlements (التسويات) — balance adjustments that never move money
// in or out of a cash box. A settlement raises or lowers the balance of one
// account (a customer, a supplier, or an expense category / بند) and posts the
// matching journal entry against the settlement account so the ledger stays
// balanced.
// ---------------------------------------------------------------------------
exports.settlementInclude = {
    customer: { select: { id: true, name: true } },
    supplier: { select: { id: true, name: true } },
    category: { select: { id: true, name: true } },
    user: { select: { id: true, name: true } },
};
/** Resolves the expense account code for a category, defaulting to 6000. */
async function resolveCategoryAccountCode(tx, categoryId) {
    const category = await tx.expenseCategory.findUnique({
        where: { id: categoryId },
        include: { account: { select: { code: true } } },
    });
    if (!category) {
        throw api_error_1.ApiError.notFound('Expense category not found', 'CATEGORY_NOT_FOUND');
    }
    return category.account?.code ?? accounting_service_1.ACCOUNT.EXPENSE;
}
/**
 * Posts the journal lines for a settlement.
 *
 * All the balancing lines are booked against the settlement account (7000) so
 * the cash account is never touched. The direction decides which side of the
 * target account moves:
 *
 * - CUSTOMER + INCREASE  → debit  Receivable, credit Settlement
 * - CUSTOMER + DECREASE  → credit Receivable, debit  Settlement
 * - SUPPLIER + INCREASE  → credit Payable,    debit  Settlement
 * - SUPPLIER + DECREASE  → debit  Payable,    credit Settlement
 * - CATEGORY + INCREASE  → debit  Expense,    credit Settlement
 * - CATEGORY + DECREASE  → credit Expense,    debit  Settlement
 */
async function postSettlementJournalTx(tx, input) {
    const { amount, direction, target } = input;
    const increase = direction === 'INCREASE';
    const targetLine = (() => {
        switch (target) {
            case 'CUSTOMER':
                return { accountCode: accounting_service_1.ACCOUNT.RECEIVABLE, debit: increase };
            case 'SUPPLIER':
                return { accountCode: accounting_service_1.ACCOUNT.PAYABLE, debit: !increase };
            case 'EXPENSE_CATEGORY':
            default:
                return { accountCode: input.accountCode, debit: increase };
        }
    })();
    await (0, accounting_service_1.postJournal)(tx, {
        memo: `Settlement ${input.number}${input.label ? ` — ${input.label}` : ''}`,
        reference: input.number,
        sourceType: 'SETTLEMENT',
        sourceId: input.settlementId,
        userId: input.userId,
        entryDate: input.settledAt,
        lines: [
            {
                accountCode: targetLine.accountCode,
                debit: targetLine.debit ? amount : 0,
                credit: targetLine.debit ? 0 : amount,
                description: `Settlement (${input.number})`,
            },
            {
                accountCode: accounting_service_1.ACCOUNT.SETTLEMENT,
                debit: targetLine.debit ? 0 : amount,
                credit: targetLine.debit ? amount : 0,
                description: `Settlement contra (${input.number})`,
            },
        ],
    });
}
/** Applies a settlement's effect to the target account's stored balance. */
async function applyBalanceTx(tx, settlement, sign) {
    const magnitude = (0, money_1.round2)(Number(settlement.amount)) * sign;
    const delta = settlement.direction === 'INCREASE' ? magnitude : -magnitude;
    if (settlement.target === 'CUSTOMER' && settlement.customerId) {
        await tx.customer.update({
            where: { id: settlement.customerId },
            data: { balance: { increment: delta } },
        });
        return;
    }
    if (settlement.target === 'SUPPLIER' && settlement.supplierId) {
        await tx.supplier.update({
            where: { id: settlement.supplierId },
            data: { balance: { increment: delta } },
        });
        return;
    }
    // Expense-category settlements only touch the ledger, so there is no stored
    // balance to update.
}
async function createSettlement(input) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const amount = (0, money_1.round2)(Math.abs(input.amount));
        if (amount <= 0) {
            throw api_error_1.ApiError.badRequest('Settlement amount must be greater than zero');
        }
        const target = input.target;
        const direction = input.direction ?? 'INCREASE';
        const settledAt = input.settledAt ?? new Date();
        const settings = await (0, settings_1.getSettings)(tx);
        let label = null;
        let accountCode = accounting_service_1.ACCOUNT.SETTLEMENT;
        let customerId = null;
        let supplierId = null;
        let categoryId = null;
        if (target === 'CUSTOMER') {
            if (!input.customerId) {
                throw api_error_1.ApiError.badRequest('A customer is required for a customer settlement');
            }
            const customer = await tx.customer.findUnique({ where: { id: input.customerId } });
            if (!customer)
                throw api_error_1.ApiError.notFound('Customer not found', 'CUSTOMER_NOT_FOUND');
            customerId = customer.id;
            label = customer.name;
        }
        else if (target === 'SUPPLIER') {
            if (!input.supplierId) {
                throw api_error_1.ApiError.badRequest('A supplier is required for a supplier settlement');
            }
            const supplier = await tx.supplier.findUnique({ where: { id: input.supplierId } });
            if (!supplier)
                throw api_error_1.ApiError.notFound('Supplier not found', 'SUPPLIER_NOT_FOUND');
            supplierId = supplier.id;
            label = supplier.name;
        }
        else if (target === 'EXPENSE_CATEGORY') {
            if (!input.categoryId) {
                throw api_error_1.ApiError.badRequest('An expense category is required for this settlement');
            }
            accountCode = await resolveCategoryAccountCode(tx, input.categoryId);
            const category = await tx.expenseCategory.findUnique({ where: { id: input.categoryId } });
            categoryId = input.categoryId;
            label = category?.name ?? null;
        }
        else {
            throw api_error_1.ApiError.badRequest('Unknown settlement target', 'BAD_TARGET');
        }
        const number = await (0, sequence_1.nextNumber)(tx, 'settlement', settings.settlementPrefix, settledAt);
        const settlement = await tx.accountSettlement.create({
            data: {
                number,
                target,
                direction,
                customerId,
                supplierId,
                categoryId,
                accountCode,
                amount,
                reference: input.reference ?? null,
                note: input.note ?? null,
                settledAt,
                userId: input.userId ?? null,
            },
            include: exports.settlementInclude,
        });
        await postSettlementJournalTx(tx, {
            settlementId: settlement.id,
            number,
            target,
            direction,
            accountCode,
            amount,
            settledAt,
            userId: input.userId,
            label,
        });
        await applyBalanceTx(tx, settlement, 1);
        if (customerId)
            await (0, invoices_service_1.recalcCustomerBalance)(tx, customerId);
        return settlement;
    });
}
/** Edits a settlement: the old entry is reversed and the balance re-applied. */
async function updateSettlement(id, input) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const settlement = await tx.accountSettlement.findUnique({ where: { id } });
        if (!settlement)
            throw api_error_1.ApiError.notFound('Settlement not found', 'SETTLEMENT_NOT_FOUND');
        if (settlement.cancelledAt) {
            throw api_error_1.ApiError.conflict('Cancelled settlements cannot be edited', 'CANCELLED_SETTLEMENT');
        }
        // Undo the previous balance effect before applying the new one.
        await applyBalanceTx(tx, settlement, -1);
        await (0, accounting_service_1.reverseJournalBySource)(tx, {
            sourceType: 'SETTLEMENT',
            sourceId: settlement.id,
            reversalSourceType: 'SETTLEMENT_EDIT',
            memo: `Settlement ${settlement.number} edited`,
            reference: settlement.number,
            userId: input.userId,
        });
        const amount = input.amount !== undefined ? (0, money_1.round2)(Math.abs(input.amount)) : (0, money_1.round2)(Number(settlement.amount));
        if (amount <= 0) {
            throw api_error_1.ApiError.badRequest('Settlement amount must be greater than zero');
        }
        const direction = input.direction ?? settlement.direction;
        const settledAt = input.settledAt ?? settlement.settledAt;
        const updated = await tx.accountSettlement.update({
            where: { id },
            data: {
                amount,
                direction,
                settledAt,
                reference: input.reference !== undefined ? input.reference : settlement.reference,
                note: input.note !== undefined ? input.note : settlement.note,
            },
            include: exports.settlementInclude,
        });
        await postSettlementJournalTx(tx, {
            settlementId: updated.id,
            number: updated.number,
            target: updated.target,
            direction,
            accountCode: updated.accountCode ?? accounting_service_1.ACCOUNT.SETTLEMENT,
            amount,
            settledAt,
            userId: input.userId,
            label: updated.customer?.name ?? updated.supplier?.name ?? updated.category?.name ?? null,
        });
        await applyBalanceTx(tx, updated, 1);
        if (updated.customerId)
            await (0, invoices_service_1.recalcCustomerBalance)(tx, updated.customerId);
        return updated;
    });
}
async function cancelSettlement(id, userId) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const settlement = await tx.accountSettlement.findUnique({ where: { id } });
        if (!settlement)
            throw api_error_1.ApiError.notFound('Settlement not found', 'SETTLEMENT_NOT_FOUND');
        if (settlement.cancelledAt) {
            throw api_error_1.ApiError.conflict('This settlement is already cancelled', 'ALREADY_CANCELLED');
        }
        await (0, accounting_service_1.reverseJournalBySource)(tx, {
            sourceType: 'SETTLEMENT',
            sourceId: settlement.id,
            reversalSourceType: 'SETTLEMENT_CANCEL',
            memo: `Settlement ${settlement.number} cancelled`,
            reference: settlement.number,
            userId,
        });
        await applyBalanceTx(tx, settlement, -1);
        const cancelled = await tx.accountSettlement.update({
            where: { id },
            data: { cancelledAt: new Date(), cancelledBy: userId ?? null },
            include: exports.settlementInclude,
        });
        if (cancelled.customerId)
            await (0, invoices_service_1.recalcCustomerBalance)(tx, cancelled.customerId);
        return cancelled;
    });
}
function settlementWhere(filter) {
    const where = {};
    if (filter.target)
        where.target = filter.target;
    if (filter.customerId)
        where.customerId = filter.customerId;
    if (filter.supplierId)
        where.supplierId = filter.supplierId;
    if (filter.categoryId)
        where.categoryId = filter.categoryId;
    if (!filter.includeCancelled)
        where.cancelledAt = null;
    if (filter.from || filter.to) {
        where.settledAt = {
            ...(filter.from ? { gte: filter.from } : {}),
            ...(filter.to ? { lte: filter.to } : {}),
        };
    }
    if (filter.search) {
        const term = filter.search;
        where.OR = [
            { number: { contains: term, mode: 'insensitive' } },
            { reference: { contains: term, mode: 'insensitive' } },
            { note: { contains: term, mode: 'insensitive' } },
            { customer: { name: { contains: term, mode: 'insensitive' } } },
            { supplier: { name: { contains: term, mode: 'insensitive' } } },
            { category: { name: { contains: term, mode: 'insensitive' } } },
        ];
    }
    return where;
}
async function listSettlements(filter) {
    const where = settlementWhere(filter);
    const [total, items] = await Promise.all([
        prisma_1.prisma.accountSettlement.count({ where }),
        prisma_1.prisma.accountSettlement.findMany({
            where,
            include: exports.settlementInclude,
            orderBy: [{ settledAt: 'desc' }, { createdAt: 'desc' }],
            skip: filter.skip ?? 0,
            take: filter.take ?? 50,
        }),
    ]);
    return { items, total };
}
async function getSettlement(id) {
    const settlement = await prisma_1.prisma.accountSettlement.findUnique({
        where: { id },
        include: exports.settlementInclude,
    });
    if (!settlement)
        throw api_error_1.ApiError.notFound('Settlement not found', 'SETTLEMENT_NOT_FOUND');
    return settlement;
}
const TARGET_LABEL = {
    CUSTOMER: 'Customer',
    SUPPLIER: 'Supplier',
    EXPENSE_CATEGORY: 'Expense category',
};
/** Builds the data for a printed settlements statement (كشف التسويات). */
async function buildSettlementStatement(filter) {
    const now = new Date();
    const from = filter.from ?? new Date(now.getFullYear(), now.getMonth(), 1);
    const to = filter.to ?? now;
    const rows = await prisma_1.prisma.accountSettlement.findMany({
        where: {
            cancelledAt: null,
            settledAt: { gte: from, lte: to },
        },
        include: exports.settlementInclude,
        orderBy: { settledAt: 'asc' },
    });
    let increaseTotal = 0;
    let decreaseTotal = 0;
    const mapped = rows.map((row) => {
        const amount = Number(row.amount);
        if (row.direction === 'INCREASE')
            increaseTotal += amount;
        else
            decreaseTotal += amount;
        return {
            number: row.number,
            settledAt: row.settledAt,
            target: TARGET_LABEL[row.target],
            accountName: row.customer?.name ?? row.supplier?.name ?? row.category?.name ?? '',
            direction: row.direction,
            amount,
            reference: row.reference,
            note: row.note,
            userName: row.user?.name ?? null,
        };
    });
    return {
        rows: mapped,
        count: mapped.length,
        increaseTotal: (0, money_1.round2)(increaseTotal),
        decreaseTotal: (0, money_1.round2)(decreaseTotal),
        netTotal: (0, money_1.round2)(increaseTotal - decreaseTotal),
        from,
        to,
    };
}
//# sourceMappingURL=settlements.service.js.map