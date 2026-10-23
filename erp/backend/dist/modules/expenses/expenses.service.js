"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.expenseCategoryInclude = exports.expenseInclude = void 0;
exports.listExpenseCategories = listExpenseCategories;
exports.createExpenseCategory = createExpenseCategory;
exports.updateExpenseCategory = updateExpenseCategory;
exports.deleteExpenseCategory = deleteExpenseCategory;
exports.createExpense = createExpense;
exports.updateExpense = updateExpense;
exports.cancelExpense = cancelExpense;
exports.listExpenses = listExpenses;
exports.buildExpenseReport = buildExpenseReport;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const sequence_1 = require("../../lib/sequence");
const settings_1 = require("../../lib/settings");
const accounting_service_1 = require("../accounting/accounting.service");
const payments_service_1 = require("../payments/payments.service");
exports.expenseInclude = {
    category: { select: { id: true, name: true } },
    cashBox: { select: { id: true, code: true, name: true } },
    user: { select: { id: true, name: true } },
};
exports.expenseCategoryInclude = {
    account: { select: { id: true, code: true, name: true } },
    _count: { select: { expenses: true } },
};
/** Resolves an account code to its id (null when not provided). */
async function resolveAccountId(accountCode) {
    if (!accountCode)
        return null;
    const account = await prisma_1.prisma.account.findUnique({ where: { code: accountCode } });
    if (!account)
        throw api_error_1.ApiError.badRequest(`Unknown account code "${accountCode}"`, 'ACCOUNT_NOT_FOUND');
    return account.id;
}
async function listExpenseCategories() {
    return prisma_1.prisma.expenseCategory.findMany({
        include: exports.expenseCategoryInclude,
        orderBy: { name: 'asc' },
    });
}
async function createExpenseCategory(input) {
    const name = input.name.trim();
    const existing = await prisma_1.prisma.expenseCategory.findUnique({ where: { name } });
    if (existing)
        throw api_error_1.ApiError.conflict('An expense category with this name already exists', 'DUPLICATE_CODE');
    const accountId = await resolveAccountId(input.accountCode);
    return prisma_1.prisma.expenseCategory.create({
        data: { name, accountId, active: input.active ?? true },
        include: exports.expenseCategoryInclude,
    });
}
async function updateExpenseCategory(id, input) {
    const category = await prisma_1.prisma.expenseCategory.findUnique({ where: { id } });
    if (!category)
        throw api_error_1.ApiError.notFound('Expense category not found', 'CATEGORY_NOT_FOUND');
    if (input.name !== undefined) {
        const name = input.name.trim();
        const clash = await prisma_1.prisma.expenseCategory.findFirst({
            where: { name, id: { not: id } },
        });
        if (clash)
            throw api_error_1.ApiError.conflict('An expense category with this name already exists', 'DUPLICATE_CODE');
    }
    const accountId = input.accountCode !== undefined ? await resolveAccountId(input.accountCode) : undefined;
    return prisma_1.prisma.expenseCategory.update({
        where: { id },
        data: {
            ...(input.name !== undefined ? { name: input.name.trim() } : {}),
            ...(accountId !== undefined ? { accountId } : {}),
            ...(input.active !== undefined ? { active: input.active } : {}),
        },
        include: exports.expenseCategoryInclude,
    });
}
async function deleteExpenseCategory(id) {
    const category = await prisma_1.prisma.expenseCategory.findUnique({
        where: { id },
        include: { _count: { select: { expenses: true } } },
    });
    if (!category)
        throw api_error_1.ApiError.notFound('Expense category not found', 'CATEGORY_NOT_FOUND');
    if (category._count.expenses > 0) {
        throw api_error_1.ApiError.conflict('This category is used by recorded expenses — deactivate it instead', 'HAS_EXPENSES');
    }
    await prisma_1.prisma.expenseCategory.delete({ where: { id } });
    return { id, deleted: true };
}
/** Resolves the expense account code, defaulting to the operating-expense account. */
async function resolveExpenseAccountCode(tx, categoryId) {
    if (!categoryId)
        return accounting_service_1.ACCOUNT.EXPENSE;
    const category = await tx.expenseCategory.findUnique({
        where: { id: categoryId },
        include: { account: { select: { code: true } } },
    });
    if (!category)
        throw api_error_1.ApiError.notFound('Expense category not found', 'CATEGORY_NOT_FOUND');
    if (!category.active)
        throw api_error_1.ApiError.badRequest('This expense category is inactive', 'CATEGORY_INACTIVE');
    return category.account?.code ?? accounting_service_1.ACCOUNT.EXPENSE;
}
async function postExpenseJournalTx(tx, input) {
    const cashAccount = input.method === 'CASH' ? accounting_service_1.ACCOUNT.CASH : accounting_service_1.ACCOUNT.BANK;
    // A negative expense (a refund, or salary drawn from the box) is booked the
    // other way round with a positive amount so the ledger never holds negative
    // debits/credits: the expense account is credited and the cash account debited.
    const reversed = input.amount < 0;
    const value = Math.abs(input.amount);
    await (0, accounting_service_1.postJournal)(tx, {
        memo: `Expense ${input.number}${input.categoryName ? ` — ${input.categoryName}` : ''}`,
        reference: input.number,
        sourceType: 'EXPENSE',
        sourceId: input.expenseId,
        userId: input.userId,
        entryDate: input.spentAt,
        lines: [
            {
                accountCode: input.accountCode,
                debit: reversed ? 0 : value,
                credit: reversed ? value : 0,
                description: `Expense (${input.number})`,
            },
            {
                accountCode: cashAccount,
                debit: reversed ? value : 0,
                credit: reversed ? 0 : value,
                description: `${reversed ? 'Cash received' : 'Cash paid'} (${input.number})`,
            },
        ],
    });
}
async function createExpense(input) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const amount = (0, money_1.round2)(input.amount);
        if (amount === 0)
            throw api_error_1.ApiError.badRequest('Expense amount cannot be zero');
        const method = input.method ?? 'CASH';
        const spentAt = input.spentAt ?? new Date();
        const accountCode = await resolveExpenseAccountCode(tx, input.categoryId);
        const box = await (0, payments_service_1.resolveCashBoxTx)(tx, input.cashBoxId);
        // Only a payment out of the box can run short; a negative expense adds cash.
        if (amount > 0) {
            const available = await (0, payments_service_1.cashBoxBalanceTx)(tx, box);
            if (amount > available + 0.01) {
                throw api_error_1.ApiError.badRequest(`Insufficient funds in cash box "${box.name}" (available ${available}, requested ${amount})`, 'INSUFFICIENT_FUNDS', { balance: available, attempted: amount, cashBoxId: box.id });
            }
        }
        const settings = await (0, settings_1.getSettings)(tx);
        const number = await (0, sequence_1.nextNumber)(tx, 'expense', settings.expensePrefix ?? 'EXP', spentAt);
        const expense = await tx.expense.create({
            data: {
                number,
                categoryId: input.categoryId ?? null,
                cashBoxId: box.id,
                accountCode,
                amount,
                method,
                payee: input.payee ?? null,
                reference: input.reference ?? null,
                note: input.note ?? null,
                spentAt,
                userId: input.userId ?? null,
            },
            include: exports.expenseInclude,
        });
        await postExpenseJournalTx(tx, {
            expenseId: expense.id,
            number,
            accountCode,
            method,
            amount,
            spentAt,
            userId: input.userId,
            categoryName: expense.category?.name ?? null,
        });
        return expense;
    });
}
async function updateExpense(id, input, userId) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const expense = await tx.expense.findUnique({ where: { id } });
        if (!expense)
            throw api_error_1.ApiError.notFound('Expense not found', 'EXPENSE_NOT_FOUND');
        if (expense.cancelledAt)
            throw api_error_1.ApiError.conflict('Cancelled expenses cannot be edited', 'CANCELLED_EXPENSE');
        const oldAmount = (0, money_1.round2)(Number(expense.amount));
        const amount = input.amount !== undefined ? (0, money_1.round2)(input.amount) : oldAmount;
        if (amount === 0)
            throw api_error_1.ApiError.badRequest('Expense amount cannot be zero');
        const method = input.method ?? expense.method;
        const spentAt = input.spentAt ?? expense.spentAt;
        const categoryId = input.categoryId !== undefined ? input.categoryId : expense.categoryId;
        const accountCode = await resolveExpenseAccountCode(tx, categoryId);
        const box = input.cashBoxId !== undefined
            ? await (0, payments_service_1.resolveCashBoxTx)(tx, input.cashBoxId)
            : expense.cashBoxId
                ? await tx.cashBox.findUnique({ where: { id: expense.cashBoxId } })
                : await (0, payments_service_1.resolveCashBoxTx)(tx, null);
        if (box && amount > 0) {
            const sameBox = expense.cashBoxId === box.id;
            const available = (0, money_1.round2)((await (0, payments_service_1.cashBoxBalanceTx)(tx, box)) + (sameBox ? oldAmount : 0));
            if (amount > available + 0.01) {
                throw api_error_1.ApiError.badRequest(`Insufficient funds in cash box "${box.name}" (available ${available}, requested ${amount})`, 'INSUFFICIENT_FUNDS', { balance: available, attempted: amount, cashBoxId: box.id });
            }
        }
        const dateChanged = spentAt.getTime() !== expense.spentAt.getTime();
        if (amount !== oldAmount || dateChanged || accountCode !== expense.accountCode) {
            await (0, accounting_service_1.reverseJournalBySource)(tx, {
                sourceType: 'EXPENSE',
                sourceId: expense.id,
                reversalSourceType: 'EXPENSE_EDIT',
                memo: `Expense ${expense.number} edited`,
                reference: expense.number,
                userId,
            });
        }
        const updated = await tx.expense.update({
            where: { id },
            data: {
                categoryId,
                ...(box ? { cashBoxId: box.id } : {}),
                accountCode,
                amount,
                method,
                ...(input.payee !== undefined ? { payee: input.payee } : {}),
                ...(input.reference !== undefined ? { reference: input.reference } : {}),
                ...(input.note !== undefined ? { note: input.note } : {}),
                spentAt,
            },
            include: exports.expenseInclude,
        });
        if (amount !== oldAmount || dateChanged || accountCode !== expense.accountCode) {
            await postExpenseJournalTx(tx, {
                expenseId: expense.id,
                number: expense.number,
                accountCode,
                method,
                amount,
                spentAt,
                userId,
                categoryName: updated.category?.name ?? null,
            });
        }
        return updated;
    });
}
async function cancelExpense(id, userId) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const expense = await tx.expense.findUnique({ where: { id } });
        if (!expense)
            throw api_error_1.ApiError.notFound('Expense not found', 'EXPENSE_NOT_FOUND');
        if (expense.cancelledAt)
            throw api_error_1.ApiError.conflict('This expense is already cancelled', 'ALREADY_CANCELLED');
        await (0, accounting_service_1.reverseJournalBySource)(tx, {
            sourceType: 'EXPENSE',
            sourceId: expense.id,
            reversalSourceType: 'EXPENSE_CANCEL',
            memo: `Expense ${expense.number} cancelled`,
            reference: expense.number,
            userId,
        });
        return tx.expense.update({
            where: { id },
            data: { cancelledAt: new Date(), cancelledBy: userId ?? null },
            include: exports.expenseInclude,
        });
    });
}
async function listExpenses(filter) {
    const where = {};
    if (!filter.includeCancelled)
        where.cancelledAt = null;
    if (filter.categoryId)
        where.categoryId = filter.categoryId;
    if (filter.cashBoxId)
        where.cashBoxId = filter.cashBoxId;
    if (filter.from || filter.to) {
        where.spentAt = {
            ...(filter.from ? { gte: filter.from } : {}),
            ...(filter.to ? { lte: filter.to } : {}),
        };
    }
    if (filter.search) {
        where.OR = [
            { number: { contains: filter.search, mode: 'insensitive' } },
            { payee: { contains: filter.search, mode: 'insensitive' } },
            { note: { contains: filter.search, mode: 'insensitive' } },
            { reference: { contains: filter.search, mode: 'insensitive' } },
        ];
    }
    const [total, items, totals] = await Promise.all([
        prisma_1.prisma.expense.count({ where }),
        prisma_1.prisma.expense.findMany({
            where,
            include: exports.expenseInclude,
            orderBy: [{ spentAt: 'desc' }, { createdAt: 'desc' }],
            skip: filter.skip ?? 0,
            take: filter.take ?? 50,
        }),
        prisma_1.prisma.expense.aggregate({
            where: { ...where, cancelledAt: null },
            _sum: { amount: true },
        }),
    ]);
    return { total, items, totalAmount: (0, money_1.round2)(Number(totals._sum.amount ?? 0)) };
}
async function buildExpenseReport(filter) {
    const where = { cancelledAt: null };
    if (filter.categoryId)
        where.categoryId = filter.categoryId;
    if (filter.cashBoxId)
        where.cashBoxId = filter.cashBoxId;
    if (filter.from || filter.to) {
        where.spentAt = {
            ...(filter.from ? { gte: filter.from } : {}),
            ...(filter.to ? { lte: filter.to } : {}),
        };
    }
    const expenses = await prisma_1.prisma.expense.findMany({
        where,
        include: exports.expenseInclude,
        orderBy: [{ spentAt: 'asc' }, { createdAt: 'asc' }],
    });
    const byCategory = new Map();
    const byMonth = new Map();
    const byBox = new Map();
    let total = 0;
    for (const expense of expenses) {
        const amount = (0, money_1.round2)(Number(expense.amount));
        total = (0, money_1.round2)(total + amount);
        const catKey = expense.categoryId ?? '__none__';
        const catEntry = byCategory.get(catKey) ?? {
            categoryId: expense.categoryId,
            name: expense.category?.name ?? 'غير مصنّف',
            amount: 0,
            count: 0,
        };
        catEntry.amount = (0, money_1.round2)(catEntry.amount + amount);
        catEntry.count += 1;
        byCategory.set(catKey, catEntry);
        const month = `${expense.spentAt.getUTCFullYear()}-${String(expense.spentAt.getUTCMonth() + 1).padStart(2, '0')}`;
        byMonth.set(month, (0, money_1.round2)((byMonth.get(month) ?? 0) + amount));
        const boxKey = expense.cashBoxId ?? '__none__';
        const boxEntry = byBox.get(boxKey) ?? {
            boxId: expense.cashBoxId,
            name: expense.cashBox?.name ?? 'غير محدد',
            amount: 0,
        };
        boxEntry.amount = (0, money_1.round2)(boxEntry.amount + amount);
        byBox.set(boxKey, boxEntry);
    }
    return {
        from: filter.from ? filter.from.toISOString() : null,
        to: filter.to ? filter.to.toISOString() : null,
        total,
        count: expenses.length,
        expenses: expenses.map((expense) => ({
            ...expense,
            amount: (0, money_1.round2)(Number(expense.amount)),
        })),
        categories: [...byCategory.values()].sort((a, b) => b.amount - a.amount),
        months: [...byMonth.entries()]
            .map(([month, amount]) => ({ month, amount }))
            .sort((a, b) => a.month.localeCompare(b.month)),
        boxes: [...byBox.values()].sort((a, b) => b.amount - a.amount),
    };
}
//# sourceMappingURL=expenses.service.js.map