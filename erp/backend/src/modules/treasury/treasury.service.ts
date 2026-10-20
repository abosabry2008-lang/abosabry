import { CashBoxType, Prisma } from '@prisma/client';
import { ApiError } from '../../lib/api-error';
import { round2 } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { nextNumber } from '../../lib/sequence';
import { cashBoxBalanceTx, cashBoxBalancesTx, ensureDefaultCashBoxTx } from '../payments/payments.service';

export const transferInclude = {
  fromBox: { select: { id: true, code: true, name: true } },
  toBox: { select: { id: true, code: true, name: true } },
  user: { select: { id: true, name: true } },
} satisfies Prisma.CashTransferInclude;

export interface CashBoxInput {
  code: string;
  name: string;
  type?: CashBoxType;
  openingBalance?: number;
  active?: boolean;
  isDefault?: boolean;
}

// ---------------------------------------------------------------------------
// Cash boxes
// ---------------------------------------------------------------------------

/** Lists boxes with their live balances (creates the default box when empty). */
export async function listCashBoxes() {
  return prisma.$transaction(async (tx) => {
    await ensureDefaultCashBoxTx(tx);
    const boxes = await tx.cashBox.findMany({
      orderBy: [{ type: 'asc' }, { createdAt: 'asc' }],
    });
    const balances = await cashBoxBalancesTx(tx, boxes);
    return boxes.map((box) => ({
      ...box,
      openingBalance: round2(Number(box.openingBalance)),
      balance: balances.get(box.id) ?? 0,
    }));
  });
}

export async function getCashBox(id: string) {
  const box = await prisma.cashBox.findUnique({ where: { id } });
  if (!box) throw ApiError.notFound('Cash box not found', 'BOX_NOT_FOUND');
  const balance = await prisma.$transaction((tx) => cashBoxBalanceTx(tx, box));
  return { ...box, openingBalance: round2(Number(box.openingBalance)), balance };
}

async function clearOtherDefaults(tx: Tx, exceptId?: string): Promise<void> {
  await tx.cashBox.updateMany({
    where: { isDefault: true, ...(exceptId ? { id: { not: exceptId } } : {}) },
    data: { isDefault: false },
  });
}

export async function createCashBox(input: CashBoxInput) {
  return prisma.$transaction(async (tx) => {
    const code = input.code.trim().toUpperCase();
    const existing = await tx.cashBox.findUnique({ where: { code } });
    if (existing) throw ApiError.conflict(`A cash box with code "${code}" already exists`, 'DUPLICATE_CODE');

    if (input.isDefault) await clearOtherDefaults(tx);

    return tx.cashBox.create({
      data: {
        code,
        name: input.name.trim(),
        type: input.type ?? 'SUB',
        openingBalance: round2(input.openingBalance ?? 0),
        active: input.active ?? true,
        isDefault: input.isDefault ?? false,
      },
    });
  });
}

export async function updateCashBox(id: string, input: Partial<CashBoxInput>) {
  return prisma.$transaction(async (tx) => {
    const box = await tx.cashBox.findUnique({ where: { id } });
    if (!box) throw ApiError.notFound('Cash box not found', 'BOX_NOT_FOUND');

    if (input.code) {
      const code = input.code.trim().toUpperCase();
      const clash = await tx.cashBox.findFirst({ where: { code, id: { not: id } } });
      if (clash) throw ApiError.conflict(`A cash box with code "${code}" already exists`, 'DUPLICATE_CODE');
    }

    if (input.isDefault) await clearOtherDefaults(tx, id);

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
        ...(input.openingBalance !== undefined ? { openingBalance: round2(input.openingBalance) } : {}),
        ...(input.active !== undefined ? { active: input.active } : {}),
        ...(input.isDefault !== undefined ? { isDefault: input.isDefault } : {}),
      },
    });
  });
}

export async function deleteCashBox(id: string) {
  return prisma.$transaction(async (tx) => {
    const box = await tx.cashBox.findUnique({ where: { id } });
    if (!box) throw ApiError.notFound('Cash box not found', 'BOX_NOT_FOUND');

    const [payments, transfers] = await Promise.all([
      tx.payment.count({ where: { cashBoxId: id } }),
      tx.cashTransfer.count({ where: { OR: [{ fromBoxId: id }, { toBoxId: id }] } }),
    ]);
    if (payments + transfers > 0) {
      throw ApiError.conflict(
        'This cash box has movements. Deactivate it instead of deleting it.',
        'BOX_HAS_MOVEMENTS',
      );
    }

    await tx.cashBox.delete({ where: { id } });

    if (box.isDefault) {
      const another = await tx.cashBox.findFirst({ orderBy: { createdAt: 'asc' } });
      if (another) await tx.cashBox.update({ where: { id: another.id }, data: { isDefault: true } });
    }
    return { id };
  });
}

// ---------------------------------------------------------------------------
// Statement of account for one box
// ---------------------------------------------------------------------------

export interface BoxStatementRow {
  date: string;
  type: 'PAYMENT_IN' | 'PAYMENT_OUT' | 'TRANSFER_IN' | 'TRANSFER_OUT' | 'EXPENSE';
  direction: 'IN' | 'OUT';
  number: string;
  description: string;
  amount: number;
  balance: number;
  method?: string;
  reference?: string | null;
  paymentId?: string;
  transferId?: string;
  expenseId?: string;
  cancelled?: boolean;
}

export interface BoxStatement {
  box: { id: string; code: string; name: string; type: CashBoxType; openingBalance: number };
  from: string | null;
  to: string | null;
  openingBalance: number;
  closingBalance: number;
  inTotal: number;
  outTotal: number;
  rows: BoxStatementRow[];
}

/** Extends a date-only bound to the last millisecond of that day. */
export function inclusiveEnd(date: Date): Date {
  const clone = new Date(date);
  if (
    clone.getUTCHours() === 0 &&
    clone.getUTCMinutes() === 0 &&
    clone.getUTCSeconds() === 0 &&
    clone.getUTCMilliseconds() === 0
  ) {
    clone.setUTCHours(23, 59, 59, 999);
  }
  return clone;
}

function rangeFilter(from?: Date, to?: Date) {
  if (!from && !to) return undefined;
  return {
    ...(from ? { gte: from } : {}),
    ...(to ? { lte: inclusiveEnd(to) } : {}),
  };
}

export async function buildCashBoxStatement(
  boxId: string,
  from?: Date,
  to?: Date,
): Promise<BoxStatement> {
  const box = await prisma.cashBox.findUnique({ where: { id: boxId } });
  if (!box) throw ApiError.notFound('Cash box not found', 'BOX_NOT_FOUND');

  const period = rangeFilter(from, to);
  const before = from ? { lt: from } : undefined;

  const [payments, transfersOut, transfersIn, expenses, beforeTotals] = await Promise.all([
    prisma.payment.findMany({
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
    prisma.cashTransfer.findMany({
      where: {
        fromBoxId: boxId,
        cancelledAt: null,
        ...(period ? { transferDate: period } : {}),
      },
      include: { toBox: { select: { name: true } } },
      orderBy: [{ transferDate: 'asc' }, { createdAt: 'asc' }],
    }),
    prisma.cashTransfer.findMany({
      where: {
        toBoxId: boxId,
        cancelledAt: null,
        ...(period ? { transferDate: period } : {}),
      },
      include: { fromBox: { select: { name: true } } },
      orderBy: [{ transferDate: 'asc' }, { createdAt: 'asc' }],
    }),
    prisma.expense.findMany({
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
          prisma.payment.aggregate({
            where: { cashBoxId: boxId, direction: 'INBOUND', cancelledAt: null, paidAt: before },
            _sum: { amount: true },
          }),
          prisma.payment.aggregate({
            where: { cashBoxId: boxId, direction: 'OUTBOUND', cancelledAt: null, paidAt: before },
            _sum: { amount: true },
          }),
          prisma.cashTransfer.aggregate({
            where: { toBoxId: boxId, cancelledAt: null, transferDate: before },
            _sum: { amount: true },
          }),
          prisma.cashTransfer.aggregate({
            where: { fromBoxId: boxId, cancelledAt: null, transferDate: before },
            _sum: { amount: true },
          }),
          prisma.expense.aggregate({
            where: { cashBoxId: boxId, cancelledAt: null, spentAt: before },
            _sum: { amount: true },
          }),
        ])
      : null,
  ]);

  let opening = round2(Number(box.openingBalance));
  if (beforeTotals) {
    const [pIn, pOut, tIn, tOut, exp] = beforeTotals;
    opening = round2(
      opening +
        Number(pIn._sum.amount ?? 0) -
        Number(pOut._sum.amount ?? 0) +
        Number(tIn._sum.amount ?? 0) -
        Number(tOut._sum.amount ?? 0) -
        Number(exp._sum.amount ?? 0),
    );
  }

  type Dated = { when: Date; createdAt: Date; kind: number; row: Omit<BoxStatementRow, 'balance'> };
  const dated: Dated[] = [];

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
        amount: round2(Number(payment.amount)),
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
        amount: round2(Number(transfer.amount)),
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
        amount: round2(Number(transfer.amount)),
        reference: transfer.reference,
        transferId: transfer.id,
      },
    });
  }

  for (const expense of expenses) {
    const description =
      [expense.category?.name, expense.payee, expense.note].filter(Boolean).join(' · ') ||
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
        amount: round2(Number(expense.amount)),
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
  const rows: BoxStatementRow[] = dated.map((entry) => {
    const signed = entry.row.direction === 'IN' ? entry.row.amount : -entry.row.amount;
    running = round2(running + signed);
    if (entry.row.direction === 'IN') inTotal = round2(inTotal + entry.row.amount);
    else outTotal = round2(outTotal + entry.row.amount);
    return { ...entry.row, balance: running };
  });

  return {
    box: {
      id: box.id,
      code: box.code,
      name: box.name,
      type: box.type,
      openingBalance: round2(Number(box.openingBalance)),
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

// ---------------------------------------------------------------------------
// Transfers between boxes
// ---------------------------------------------------------------------------

export interface CreateTransferInput {
  fromBoxId: string;
  toBoxId: string;
  amount: number;
  exchangeRate?: number;
  reference?: string | null;
  note?: string | null;
  transferDate?: Date | null;
  userId?: string;
}

export interface UpdateTransferInput {
  amount?: number;
  reference?: string | null;
  note?: string | null;
  transferDate?: Date | null;
}

export async function createTransfer(input: CreateTransferInput) {
  return prisma.$transaction(async (tx) => {
    if (input.fromBoxId === input.toBoxId) {
      throw ApiError.badRequest('Source and destination boxes must differ', 'SAME_BOX');
    }
    const amount = round2(input.amount);
    if (amount <= 0) throw ApiError.badRequest('Transfer amount must be greater than zero');

    const from = await tx.cashBox.findUnique({ where: { id: input.fromBoxId } });
    if (!from) throw ApiError.notFound('Source cash box not found', 'BOX_NOT_FOUND');
    const to = await tx.cashBox.findUnique({ where: { id: input.toBoxId } });
    if (!to) throw ApiError.notFound('Destination cash box not found', 'BOX_NOT_FOUND');
    if (!from.active) throw ApiError.badRequest('Source cash box is inactive', 'BOX_INACTIVE');
    if (!to.active) throw ApiError.badRequest('Destination cash box is inactive', 'BOX_INACTIVE');

    const available = await cashBoxBalanceTx(tx, from);
    if (amount > available + 0.01) {
      throw ApiError.badRequest(
        `Insufficient funds in cash box "${from.name}" (available ${available}, requested ${amount})`,
        'INSUFFICIENT_FUNDS',
        { balance: available, attempted: amount, cashBoxId: from.id },
      );
    }

    const transferDate = input.transferDate ?? new Date();
    const number = await nextNumber(tx, 'transfer', 'TRF', transferDate);

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
      include: transferInclude,
    });
  });
}

export async function updateTransfer(id: string, input: UpdateTransferInput) {
  return prisma.$transaction(async (tx) => {
    const transfer = await tx.cashTransfer.findUnique({ where: { id } });
    if (!transfer) throw ApiError.notFound('Transfer not found', 'TRANSFER_NOT_FOUND');
    if (transfer.cancelledAt) {
      throw ApiError.conflict('Cancelled transfers cannot be edited', 'CANCELLED_TRANSFER');
    }

    const amount = input.amount !== undefined ? round2(input.amount) : round2(Number(transfer.amount));
    if (amount <= 0) throw ApiError.badRequest('Transfer amount must be greater than zero');

    if (amount > round2(Number(transfer.amount))) {
      const from = await tx.cashBox.findUnique({ where: { id: transfer.fromBoxId } });
      if (!from) throw ApiError.notFound('Source cash box not found', 'BOX_NOT_FOUND');
      // The current transfer already counts as an outflow; add it back before
      // checking whether the larger amount still fits.
      const available = round2((await cashBoxBalanceTx(tx, from)) + Number(transfer.amount));
      if (amount > available + 0.01) {
        throw ApiError.badRequest(
          `Insufficient funds in cash box "${from.name}" (available ${available}, requested ${amount})`,
          'INSUFFICIENT_FUNDS',
          { balance: available, attempted: amount, cashBoxId: from.id },
        );
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
      include: transferInclude,
    });
  });
}

export async function cancelTransfer(id: string, userId?: string) {
  return prisma.$transaction(async (tx) => {
    const transfer = await tx.cashTransfer.findUnique({ where: { id } });
    if (!transfer) throw ApiError.notFound('Transfer not found', 'TRANSFER_NOT_FOUND');
    if (transfer.cancelledAt) throw ApiError.conflict('This transfer is already cancelled', 'ALREADY_CANCELLED');

    return tx.cashTransfer.update({
      where: { id },
      data: { cancelledAt: new Date(), cancelledBy: userId ?? null },
      include: transferInclude,
    });
  });
}

export async function listTransfers(filter: { boxId?: string; from?: Date; to?: Date; limit?: number }) {
  const period = rangeFilter(filter.from, filter.to);
  return prisma.cashTransfer.findMany({
    where: {
      ...(filter.boxId ? { OR: [{ fromBoxId: filter.boxId }, { toBoxId: filter.boxId }] } : {}),
      ...(period ? { transferDate: period } : {}),
    },
    include: transferInclude,
    orderBy: [{ transferDate: 'desc' }, { createdAt: 'desc' }],
    take: filter.limit ?? 100,
  });
}
