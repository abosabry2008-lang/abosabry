import { PaymentMethod, Prisma } from '@prisma/client';
import { ApiError } from '../../lib/api-error';
import { round2 } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { nextNumber } from '../../lib/sequence';
import { getSettings } from '../../lib/settings';
import { ACCOUNT, postJournal, reverseJournalBySource } from '../accounting/accounting.service';
import { cashBoxBalanceTx, resolveCashBoxTx } from '../payments/payments.service';

export const expenseInclude = {
  category: { select: { id: true, name: true } },
  cashBox: { select: { id: true, code: true, name: true } },
  user: { select: { id: true, name: true } },
} satisfies Prisma.ExpenseInclude;

export const expenseCategoryInclude = {
  account: { select: { id: true, code: true, name: true } },
  _count: { select: { expenses: true } },
} satisfies Prisma.ExpenseCategoryInclude;

// ---------------------------------------------------------------------------
// Expense categories (تصنيفات المصروفات)
// ---------------------------------------------------------------------------

export interface ExpenseCategoryInput {
  name: string;
  accountCode?: string | null;
  active?: boolean;
}

/** Resolves an account code to its id (null when not provided). */
async function resolveAccountId(accountCode?: string | null): Promise<string | null> {
  if (!accountCode) return null;
  const account = await prisma.account.findUnique({ where: { code: accountCode } });
  if (!account) throw ApiError.badRequest(`Unknown account code "${accountCode}"`, 'ACCOUNT_NOT_FOUND');
  return account.id;
}

export async function listExpenseCategories() {
  return prisma.expenseCategory.findMany({
    include: expenseCategoryInclude,
    orderBy: { name: 'asc' },
  });
}

export async function createExpenseCategory(input: ExpenseCategoryInput) {
  const name = input.name.trim();
  const existing = await prisma.expenseCategory.findUnique({ where: { name } });
  if (existing) throw ApiError.conflict('An expense category with this name already exists', 'DUPLICATE_CODE');
  const accountId = await resolveAccountId(input.accountCode);
  return prisma.expenseCategory.create({
    data: { name, accountId, active: input.active ?? true },
    include: expenseCategoryInclude,
  });
}

export async function updateExpenseCategory(id: string, input: Partial<ExpenseCategoryInput>) {
  const category = await prisma.expenseCategory.findUnique({ where: { id } });
  if (!category) throw ApiError.notFound('Expense category not found', 'CATEGORY_NOT_FOUND');

  if (input.name !== undefined) {
    const name = input.name.trim();
    const clash = await prisma.expenseCategory.findFirst({
      where: { name, id: { not: id } },
    });
    if (clash) throw ApiError.conflict('An expense category with this name already exists', 'DUPLICATE_CODE');
  }

  const accountId =
    input.accountCode !== undefined ? await resolveAccountId(input.accountCode) : undefined;

  return prisma.expenseCategory.update({
    where: { id },
    data: {
      ...(input.name !== undefined ? { name: input.name.trim() } : {}),
      ...(accountId !== undefined ? { accountId } : {}),
      ...(input.active !== undefined ? { active: input.active } : {}),
    },
    include: expenseCategoryInclude,
  });
}

export async function deleteExpenseCategory(id: string) {
  const category = await prisma.expenseCategory.findUnique({
    where: { id },
    include: { _count: { select: { expenses: true } } },
  });
  if (!category) throw ApiError.notFound('Expense category not found', 'CATEGORY_NOT_FOUND');
  if (category._count.expenses > 0) {
    throw ApiError.conflict(
      'This category is used by recorded expenses — deactivate it instead',
      'HAS_EXPENSES',
    );
  }
  await prisma.expenseCategory.delete({ where: { id } });
  return { id, deleted: true };
}

// ---------------------------------------------------------------------------
// Expenses (المصروفات)
// ---------------------------------------------------------------------------

export interface CreateExpenseInput {
  categoryId?: string | null;
  cashBoxId?: string | null;
  amount: number;
  method?: PaymentMethod;
  payee?: string | null;
  reference?: string | null;
  note?: string | null;
  spentAt?: Date | null;
  userId?: string;
}

export interface UpdateExpenseInput {
  categoryId?: string | null;
  cashBoxId?: string | null;
  amount?: number;
  method?: PaymentMethod;
  payee?: string | null;
  reference?: string | null;
  note?: string | null;
  spentAt?: Date | null;
}

/** Resolves the expense account code, defaulting to the operating-expense account. */
async function resolveExpenseAccountCode(tx: Tx, categoryId?: string | null): Promise<string> {
  if (!categoryId) return ACCOUNT.EXPENSE;
  const category = await tx.expenseCategory.findUnique({
    where: { id: categoryId },
    include: { account: { select: { code: true } } },
  });
  if (!category) throw ApiError.notFound('Expense category not found', 'CATEGORY_NOT_FOUND');
  if (!category.active) throw ApiError.badRequest('This expense category is inactive', 'CATEGORY_INACTIVE');
  return category.account?.code ?? ACCOUNT.EXPENSE;
}

async function postExpenseJournalTx(
  tx: Tx,
  input: {
    expenseId: string;
    number: string;
    accountCode: string;
    method: PaymentMethod;
    amount: number;
    spentAt: Date;
    userId?: string;
    categoryName?: string | null;
  },
): Promise<void> {
  const cashAccount = input.method === 'CASH' ? ACCOUNT.CASH : ACCOUNT.BANK;
  // A negative expense (a refund, or salary drawn from the box) is booked the
  // other way round with a positive amount so the ledger never holds negative
  // debits/credits: the expense account is credited and the cash account debited.
  const reversed = input.amount < 0;
  const value = Math.abs(input.amount);
  await postJournal(tx, {
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

export async function createExpense(input: CreateExpenseInput) {
  return prisma.$transaction(async (tx) => {
    const amount = round2(input.amount);
    if (amount === 0) throw ApiError.badRequest('Expense amount cannot be zero');

    const method: PaymentMethod = input.method ?? 'CASH';
    const spentAt = input.spentAt ?? new Date();
    const accountCode = await resolveExpenseAccountCode(tx, input.categoryId);
    const box = await resolveCashBoxTx(tx, input.cashBoxId);

    // Only a payment out of the box can run short; a negative expense adds cash.
    if (amount > 0) {
      const available = await cashBoxBalanceTx(tx, box);
      if (amount > available + 0.01) {
        throw ApiError.badRequest(
          `Insufficient funds in cash box "${box.name}" (available ${available}, requested ${amount})`,
          'INSUFFICIENT_FUNDS',
          { balance: available, attempted: amount, cashBoxId: box.id },
        );
      }
    }

    const settings = await getSettings(tx);
    const number = await nextNumber(
      tx,
      'expense',
      settings.expensePrefix ?? 'EXP',
      spentAt,
      async (candidate) => (await tx.expense.count({ where: { number: candidate } })) > 0,
    );

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
      include: expenseInclude,
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

export async function updateExpense(id: string, input: UpdateExpenseInput, userId?: string) {
  return prisma.$transaction(async (tx) => {
    const expense = await tx.expense.findUnique({ where: { id } });
    if (!expense) throw ApiError.notFound('Expense not found', 'EXPENSE_NOT_FOUND');
    if (expense.cancelledAt) throw ApiError.conflict('Cancelled expenses cannot be edited', 'CANCELLED_EXPENSE');

    const oldAmount = round2(Number(expense.amount));
    const amount = input.amount !== undefined ? round2(input.amount) : oldAmount;
    if (amount === 0) throw ApiError.badRequest('Expense amount cannot be zero');

    const method: PaymentMethod = input.method ?? expense.method;
    const spentAt = input.spentAt ?? expense.spentAt;
    const categoryId = input.categoryId !== undefined ? input.categoryId : expense.categoryId;
    const accountCode = await resolveExpenseAccountCode(tx, categoryId);

    const box =
      input.cashBoxId !== undefined
        ? await resolveCashBoxTx(tx, input.cashBoxId)
        : expense.cashBoxId
          ? await tx.cashBox.findUnique({ where: { id: expense.cashBoxId } })
          : await resolveCashBoxTx(tx, null);

    if (box && amount > 0) {
      const sameBox = expense.cashBoxId === box.id;
      const available = round2((await cashBoxBalanceTx(tx, box)) + (sameBox ? oldAmount : 0));
      if (amount > available + 0.01) {
        throw ApiError.badRequest(
          `Insufficient funds in cash box "${box.name}" (available ${available}, requested ${amount})`,
          'INSUFFICIENT_FUNDS',
          { balance: available, attempted: amount, cashBoxId: box.id },
        );
      }
    }

    const dateChanged = spentAt.getTime() !== expense.spentAt.getTime();
    if (amount !== oldAmount || dateChanged || accountCode !== expense.accountCode) {
      await reverseJournalBySource(tx, {
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
      include: expenseInclude,
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

export async function cancelExpense(id: string, userId?: string) {
  return prisma.$transaction(async (tx) => {
    const expense = await tx.expense.findUnique({ where: { id } });
    if (!expense) throw ApiError.notFound('Expense not found', 'EXPENSE_NOT_FOUND');
    if (expense.cancelledAt) throw ApiError.conflict('This expense is already cancelled', 'ALREADY_CANCELLED');

    await reverseJournalBySource(tx, {
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
      include: expenseInclude,
    });
  });
}

export interface ListExpensesFilter {
  from?: Date;
  to?: Date;
  categoryId?: string;
  cashBoxId?: string;
  includeCancelled?: boolean;
  search?: string;
  skip?: number;
  take?: number;
}

export async function listExpenses(filter: ListExpensesFilter) {
  const where: Prisma.ExpenseWhereInput = {};
  if (!filter.includeCancelled) where.cancelledAt = null;
  if (filter.categoryId) where.categoryId = filter.categoryId;
  if (filter.cashBoxId) where.cashBoxId = filter.cashBoxId;
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
    prisma.expense.count({ where }),
    prisma.expense.findMany({
      where,
      include: expenseInclude,
      orderBy: [{ spentAt: 'desc' }, { createdAt: 'desc' }],
      skip: filter.skip ?? 0,
      take: filter.take ?? 50,
    }),
    prisma.expense.aggregate({
      where: { ...where, cancelledAt: null },
      _sum: { amount: true },
    }),
  ]);

  return { total, items, totalAmount: round2(Number(totals._sum.amount ?? 0)) };
}

// ---------------------------------------------------------------------------
// Expense report (تقرير المصروفات)
// ---------------------------------------------------------------------------

export interface ExpenseReportFilter {
  from?: Date;
  to?: Date;
  categoryId?: string;
  cashBoxId?: string;
}

export async function buildExpenseReport(filter: ExpenseReportFilter) {
  const where: Prisma.ExpenseWhereInput = { cancelledAt: null };
  if (filter.categoryId) where.categoryId = filter.categoryId;
  if (filter.cashBoxId) where.cashBoxId = filter.cashBoxId;
  if (filter.from || filter.to) {
    where.spentAt = {
      ...(filter.from ? { gte: filter.from } : {}),
      ...(filter.to ? { lte: filter.to } : {}),
    };
  }

  const expenses = await prisma.expense.findMany({
    where,
    include: expenseInclude,
    orderBy: [{ spentAt: 'asc' }, { createdAt: 'asc' }],
  });

  const byCategory = new Map<string, { categoryId: string | null; name: string; amount: number; count: number }>();
  const byMonth = new Map<string, number>();
  const byBox = new Map<string, { boxId: string | null; name: string; amount: number }>();

  let total = 0;
  for (const expense of expenses) {
    const amount = round2(Number(expense.amount));
    total = round2(total + amount);

    const catKey = expense.categoryId ?? '__none__';
    const catEntry = byCategory.get(catKey) ?? {
      categoryId: expense.categoryId,
      name: expense.category?.name ?? 'غير مصنّف',
      amount: 0,
      count: 0,
    };
    catEntry.amount = round2(catEntry.amount + amount);
    catEntry.count += 1;
    byCategory.set(catKey, catEntry);

    const month = `${expense.spentAt.getUTCFullYear()}-${String(expense.spentAt.getUTCMonth() + 1).padStart(2, '0')}`;
    byMonth.set(month, round2((byMonth.get(month) ?? 0) + amount));

    const boxKey = expense.cashBoxId ?? '__none__';
    const boxEntry = byBox.get(boxKey) ?? {
      boxId: expense.cashBoxId,
      name: expense.cashBox?.name ?? 'غير محدد',
      amount: 0,
    };
    boxEntry.amount = round2(boxEntry.amount + amount);
    byBox.set(boxKey, boxEntry);
  }

  return {
    from: filter.from ? filter.from.toISOString() : null,
    to: filter.to ? filter.to.toISOString() : null,
    total,
    count: expenses.length,
    expenses: expenses.map((expense) => ({
      ...expense,
      amount: round2(Number(expense.amount)),
    })),
    categories: [...byCategory.values()].sort((a, b) => b.amount - a.amount),
    months: [...byMonth.entries()]
      .map(([month, amount]) => ({ month, amount }))
      .sort((a, b) => a.month.localeCompare(b.month)),
    boxes: [...byBox.values()].sort((a, b) => b.amount - a.amount),
  };
}
