import { CashBox, PaymentDirection, PaymentMethod, Prisma } from '@prisma/client';
import { randomUUID } from 'crypto';
import { ApiError } from '../../lib/api-error';
import { round2 } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { nextNumber, nextNumbers } from '../../lib/sequence';
import { getSettings } from '../../lib/settings';
import {
  ACCOUNT,
  postJournal,
  postJournalBatch,
  reverseJournalBySource,
} from '../accounting/accounting.service';
import { recalcCustomerBalance } from '../invoices/invoices.service';

export const paymentInclude = {
  customer: { select: { id: true, name: true } },
  supplier: { select: { id: true, name: true } },
  invoice: { select: { id: true, number: true, total: true, balance: true, status: true } },
  currency: { select: { id: true, code: true, symbol: true } },
  user: { select: { id: true, name: true } },
  cashBox: { select: { id: true, code: true, name: true } },
  collectionVoucher: { select: { id: true, number: true } },
} satisfies Prisma.PaymentInclude;

export interface CreatePaymentInput {
  direction?: PaymentDirection;
  invoiceId?: string | null;
  customerId?: string | null;
  supplierId?: string | null;
  currencyId?: string | null;
  /** Cash box that receives (INBOUND) or funds (OUTBOUND) the payment. */
  cashBoxId?: string | null;
  /** Set when the payment was generated from an agent collection receipt. */
  collectionVoucherId?: string | null;
  method?: PaymentMethod;
  amount: number;
  reference?: string | null;
  note?: string | null;
  paidAt?: Date | null;
  userId?: string;
}

// ---------------------------------------------------------------------------
// Cash boxes
// ---------------------------------------------------------------------------

/**
 * Returns the default cash box, creating a "main box" the first time the
 * treasury is used so payment forms always have somewhere to post to.
 */
export async function ensureDefaultCashBoxTx(tx: Tx): Promise<CashBox> {
  const existing =
    (await tx.cashBox.findFirst({ where: { isDefault: true, active: true }, orderBy: { createdAt: 'asc' } })) ??
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
export async function resolveCashBoxTx(tx: Tx, cashBoxId?: string | null): Promise<CashBox> {
  if (!cashBoxId) return ensureDefaultCashBoxTx(tx);

  const box = await tx.cashBox.findUnique({ where: { id: cashBoxId } });
  if (!box) throw ApiError.notFound('Cash box not found', 'BOX_NOT_FOUND');
  if (!box.active) throw ApiError.badRequest('This cash box is inactive', 'BOX_INACTIVE');
  return box;
}

/**
 * Current balance of a box: its opening balance plus every live (non
 * cancelled) payment and transfer that touches it. Computing on read keeps the
 * figure correct even after an admin edits or cancels a movement.
 */
export async function cashBoxBalanceTx(tx: Tx, box: Pick<CashBox, 'id' | 'openingBalance'>): Promise<number> {
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

  return round2(
    Number(box.openingBalance) +
      Number(paymentsIn._sum.amount ?? 0) -
      Number(paymentsOut._sum.amount ?? 0) +
      Number(transfersIn._sum.amount ?? 0) -
      Number(transfersOut._sum.amount ?? 0) -
      Number(expenses._sum.amount ?? 0),
  );
}

/** Balances for many boxes with aggregate queries (used by the list screen). */
export async function cashBoxBalancesTx(
  tx: Tx,
  boxes: Pick<CashBox, 'id' | 'openingBalance'>[],
): Promise<Map<string, number>> {
  const balances = new Map<string, number>();
  if (boxes.length === 0) return balances;

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

  for (const box of boxes) balances.set(box.id, round2(Number(box.openingBalance)));

  for (const row of payments) {
    if (!row.cashBoxId) continue;
    const current = balances.get(row.cashBoxId) ?? 0;
    const amount = Number(row._sum.amount ?? 0);
    balances.set(row.cashBoxId, round2(current + (row.direction === 'INBOUND' ? amount : -amount)));
  }
  for (const row of transfersIn) {
    const current = balances.get(row.toBoxId) ?? 0;
    balances.set(row.toBoxId, round2(current + Number(row._sum.amount ?? 0)));
  }
  for (const row of transfersOut) {
    const current = balances.get(row.fromBoxId) ?? 0;
    balances.set(row.fromBoxId, round2(current - Number(row._sum.amount ?? 0)));
  }
  for (const row of expenses) {
    if (!row.cashBoxId) continue;
    const current = balances.get(row.cashBoxId) ?? 0;
    balances.set(row.cashBoxId, round2(current - Number(row._sum.amount ?? 0)));
  }

  return balances;
}

// ---------------------------------------------------------------------------
// Journal posting
// ---------------------------------------------------------------------------

async function postPaymentJournalTx(
  tx: Tx,
  input: {
    paymentId: string;
    number: string;
    direction: PaymentDirection;
    method: PaymentMethod;
    amount: number;
    paidAt: Date;
    userId?: string;
    memo?: string;
    /** Overrides the AR/AP contra account (used for walk-in cash sales). */
    contraAccount?: string;
    cashSale?: boolean;
  },
): Promise<void> {
  const cashAccount = input.method === 'CASH' ? ACCOUNT.CASH : ACCOUNT.BANK;
  const contra = input.cashSale
    ? ACCOUNT.REVENUE
    : input.contraAccount ??
      (input.direction === 'INBOUND' ? ACCOUNT.RECEIVABLE : ACCOUNT.PAYABLE);
  await postJournal(tx, {
    memo: input.memo ?? (input.cashSale ? `Cash sale ${input.number}` : `Payment ${input.number}`),
    reference: input.number,
    sourceType: 'PAYMENT',
    sourceId: input.paymentId,
    userId: input.userId,
    entryDate: input.paidAt,
    lines:
      input.direction === 'INBOUND'
        ? [
            {
              accountCode: cashAccount,
              debit: input.amount,
              description: input.cashSale
                ? `Cash sale (${input.number})`
                : `Funds received (${input.number})`,
            },
            {
              accountCode: contra,
              credit: input.amount,
              description: input.cashSale
                ? `Cash sale revenue (${input.number})`
                : `Receipt (${input.number})`,
            },
          ]
        : [
            { accountCode: contra, debit: input.amount, description: `Payable settled (${input.number})` },
            { accountCode: cashAccount, credit: input.amount, description: `Funds paid (${input.number})` },
          ],
  });
}

// ---------------------------------------------------------------------------
// Creating payments
// ---------------------------------------------------------------------------

export async function createPaymentTx(tx: Tx, input: CreatePaymentInput) {
  if (input.amount <= 0) throw ApiError.badRequest('Payment amount must be greater than zero');

  const method: PaymentMethod = input.method ?? 'CASH';
  const direction: PaymentDirection = input.direction ?? 'INBOUND';
  const paidAt = input.paidAt ?? new Date();
  const amount = round2(input.amount);
  const settings = await getSettings(tx);
  const number = await nextNumber(
    tx,
    'payment',
    settings.paymentPrefix,
    paidAt,
    async (candidate) => (await tx.payment.count({ where: { number: candidate } })) > 0,
  );
  const box = await resolveCashBoxTx(tx, input.cashBoxId);

  if (input.invoiceId) {
    const invoice = await tx.invoice.findUnique({ where: { id: input.invoiceId } });
    if (!invoice) throw ApiError.notFound('Invoice not found');
    if (invoice.status === 'VOID' || invoice.status === 'DRAFT') {
      throw ApiError.badRequest('Only issued invoices can receive payments', 'NOT_PAYABLE');
    }

    const balance = round2(Number(invoice.balance));
    if (amount > balance + 0.01) {
      throw ApiError.badRequest(`Payment exceeds the outstanding balance of ${balance}`, 'OVERPAYMENT', {
        balance,
        attempted: amount,
      });
    }

    const amountPaid = round2(Number(invoice.amountPaid) + amount);
    const newBalance = round2(Math.max(0, balance - amount));

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
      include: paymentInclude,
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

    if (invoice.customerId) await recalcCustomerBalance(tx, invoice.customerId);
    return payment;
  }

  // Outbound money must actually exist in the box it is paid from.
  if (direction === 'OUTBOUND') {
    const available = await cashBoxBalanceTx(tx, box);
    if (amount > available + 0.01) {
      throw ApiError.badRequest(
        `Insufficient funds in cash box "${box.name}" (available ${available}, requested ${amount})`,
        'INSUFFICIENT_FUNDS',
        { balance: available, attempted: amount, cashBoxId: box.id },
      );
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
      include: paymentInclude,
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
    include: paymentInclude,
  });

  // A receipt with no customer or supplier is a walk-in cash sale: the money
  // goes straight to the cash box and the credit side is revenue, not AR.
  const cashSale =
    direction === 'INBOUND' && !input.customerId && !input.supplierId;
  await postPaymentJournalTx(tx, {
    paymentId: payment.id,
    number,
    direction,
    method,
    amount,
    paidAt,
    userId: input.userId,
    cashSale,
  });

  // An on-account receipt changes the customer's balance even though it is not
  // tied to an invoice, so the stored balance must be refreshed here.
  if (payment.customerId) await recalcCustomerBalance(tx, payment.customerId);

  return payment;
}

export async function createPayment(input: CreatePaymentInput) {
  return prisma.$transaction((tx) => createPaymentTx(tx, input));
}

// ---------------------------------------------------------------------------
// Cancelling / editing payments
// ---------------------------------------------------------------------------

/** Recomputes an invoice's paid amount, balance and status from its live payments. */
async function syncInvoicePaidTx(tx: Tx, invoiceId: string): Promise<void> {
  const invoice = await tx.invoice.findUnique({ where: { id: invoiceId } });
  if (!invoice || invoice.status === 'VOID') return;

  const paid = await tx.payment.aggregate({
    where: { invoiceId, cancelledAt: null, direction: 'INBOUND' },
    _sum: { amount: true },
  });
  const amountPaid = round2(Number(paid._sum.amount ?? 0));
  const balance = round2(Math.max(0, Number(invoice.total) - amountPaid));
  const status = balance <= 0.01 ? 'PAID' : amountPaid > 0 ? 'PARTIALLY_PAID' : 'ISSUED';

  await tx.invoice.update({ where: { id: invoiceId }, data: { amountPaid, balance, status } });
  if (invoice.customerId) await recalcCustomerBalance(tx, invoice.customerId);
}

/**
 * Cancels a payment: reverses its journal entry, marks it cancelled (which
 * removes it from box balances and statements) and restores the invoice and
 * supplier balances it had changed.
 */
export async function cancelPaymentTx(tx: Tx, paymentId: string, userId?: string) {
  const payment = await tx.payment.findUnique({ where: { id: paymentId } });
  if (!payment) throw ApiError.notFound('Payment not found');
  if (payment.cancelledAt) throw ApiError.conflict('This payment is already cancelled', 'ALREADY_CANCELLED');

  await reverseJournalBySource(tx, {
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

  if (payment.invoiceId) await syncInvoicePaidTx(tx, payment.invoiceId);

  if (!payment.invoiceId && payment.customerId) {
    await recalcCustomerBalance(tx, payment.customerId);
  }

  if (payment.supplierId && payment.direction === 'OUTBOUND' && !payment.invoiceId) {
    await tx.supplier.update({
      where: { id: payment.supplierId },
      data: { balance: { increment: round2(Number(payment.amount)) } },
    });
  }

  return tx.payment.findUniqueOrThrow({ where: { id: payment.id }, include: paymentInclude });
}

/** Cancels a standalone payment (collection receipt lines are cancelled through their receipt). */
export async function cancelPayment(paymentId: string, userId?: string) {
  return prisma.$transaction(async (tx) => {
    const payment = await tx.payment.findUnique({ where: { id: paymentId } });
    if (!payment) throw ApiError.notFound('Payment not found');
    if (payment.collectionVoucherId) {
      throw ApiError.badRequest(
        'This payment belongs to a collection receipt — cancel the receipt instead',
        'COLLECTION_PAYMENT',
      );
    }
    return cancelPaymentTx(tx, paymentId, userId);
  });
}

export interface UpdatePaymentInput {
  amount?: number;
  cashBoxId?: string | null;
  note?: string | null;
  reference?: string | null;
  paidAt?: Date | null;
}

export async function updatePaymentTx(tx: Tx, paymentId: string, input: UpdatePaymentInput, userId?: string) {
  const payment = await tx.payment.findUnique({ where: { id: paymentId }, include: { invoice: true } });
  if (!payment) throw ApiError.notFound('Payment not found');
  if (payment.cancelledAt) throw ApiError.conflict('Cancelled payments cannot be edited', 'CANCELLED_PAYMENT');
  if (payment.collectionVoucherId) {
    throw ApiError.badRequest(
      'This payment belongs to a collection receipt — cancel the receipt and record a new one',
      'COLLECTION_PAYMENT',
    );
  }

  const oldAmount = round2(Number(payment.amount));
  const amount = input.amount !== undefined ? round2(input.amount) : oldAmount;
  if (amount <= 0) throw ApiError.badRequest('Payment amount must be greater than zero');

  if (payment.invoiceId && amount !== oldAmount) {
    const invoice = payment.invoice;
    if (!invoice) throw ApiError.notFound('Invoice not found');
    const others = await tx.payment.aggregate({
      where: { invoiceId: payment.invoiceId, cancelledAt: null, id: { not: payment.id } },
      _sum: { amount: true },
    });
    const maxAmount = round2(Number(invoice.total) - Number(others._sum.amount ?? 0));
    if (amount > maxAmount + 0.01) {
      throw ApiError.badRequest(`Payment exceeds the outstanding balance of ${maxAmount}`, 'OVERPAYMENT', {
        balance: maxAmount,
        attempted: amount,
      });
    }
  }

  const targetBox =
    input.cashBoxId !== undefined
      ? await resolveCashBoxTx(tx, input.cashBoxId)
      : payment.cashBoxId
        ? await tx.cashBox.findUnique({ where: { id: payment.cashBoxId } })
        : null;

  if (payment.direction === 'OUTBOUND' && targetBox) {
    const sameBox = payment.cashBoxId === targetBox.id;
    const available = round2((await cashBoxBalanceTx(tx, targetBox)) + (sameBox ? oldAmount : 0));
    if (amount > available + 0.01) {
      throw ApiError.badRequest(
        `Insufficient funds in cash box "${targetBox.name}" (available ${available}, requested ${amount})`,
        'INSUFFICIENT_FUNDS',
        { balance: available, attempted: amount, cashBoxId: targetBox.id },
      );
    }
  }

  const paidAt = input.paidAt ?? payment.paidAt;
  const dateChanged = paidAt.getTime() !== payment.paidAt.getTime();

  if (amount !== oldAmount || dateChanged) {
    await reverseJournalBySource(tx, {
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
    include: paymentInclude,
  });

  if (payment.invoiceId) await syncInvoicePaidTx(tx, payment.invoiceId);

  if (
    amount !== oldAmount &&
    payment.supplierId &&
    payment.direction === 'OUTBOUND' &&
    !payment.invoiceId
  ) {
    await tx.supplier.update({
      where: { id: payment.supplierId },
      data: { balance: { decrement: round2(amount - oldAmount) } },
    });
  }

  return updated;
}

export async function updatePayment(paymentId: string, input: UpdatePaymentInput, userId?: string) {
  return prisma.$transaction((tx) => updatePaymentTx(tx, paymentId, input, userId));
}

// ---------------------------------------------------------------------------
// Agent collection receipts (multiple customers / invoices in one voucher)
// ---------------------------------------------------------------------------

export const collectionInclude = {
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
} satisfies Prisma.CollectionVoucherInclude;

export interface CollectionLineInput {
  customerId?: string | null;
  invoiceId?: string | null;
  /** Optional per-line cash box; falls back to the receipt's box. */
  cashBoxId?: string | null;
  amount: number;
  note?: string | null;
}

export interface CreateCollectionInput {
  cashBoxId?: string | null;
  salespersonId?: string | null;
  collectedAt?: Date | null;
  reference?: string | null;
  note?: string | null;
  lines: CollectionLineInput[];
  userId?: string;
}

export async function createCollectionTx(tx: Tx, input: CreateCollectionInput) {
  if (!input.lines || input.lines.length === 0) {
    throw ApiError.badRequest('A collection receipt needs at least one line', 'NO_LINES');
  }
  if (input.lines.some((line) => !(line.amount > 0))) {
    throw ApiError.badRequest('Every collection line needs a positive amount', 'INVALID_LINE');
  }

  const box = await resolveCashBoxTx(tx, input.cashBoxId);
  const collectedAt = input.collectedAt ?? new Date();

  if (input.salespersonId) {
    const salesperson = await tx.user.findUnique({ where: { id: input.salespersonId } });
    if (!salesperson) throw ApiError.badRequest('Salesperson not found', 'SALESPERSON_NOT_FOUND');
  }

  const number = await nextNumber(
    tx,
    'collection',
    'COL',
    collectedAt,
    async (candidate) => (await tx.collectionVoucher.count({ where: { number: candidate } })) > 0,
  );

  // Fast path for the bulk screen: one amount per customer and no invoice to
  // apply. Everything is inserted in batches instead of paying the per-line
  // settings/number/journal overhead 50 times inside the transaction.
  if (input.lines.every((line) => !line.invoiceId)) {
    return createBulkCollectionTx(tx, input, { box, collectedAt, number });
  }

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
    let invoice: { id: string; number: string; customerId: string | null } | null = null;
    if (line.invoiceId) {
      invoice = await tx.invoice.findUnique({
        where: { id: line.invoiceId },
        select: { id: true, number: true, customerId: true },
      });
      if (!invoice) throw ApiError.notFound('Invoice not found');
    }

    if (line.customerId && invoice?.customerId && invoice.customerId !== line.customerId) {
      throw ApiError.badRequest('The invoice belongs to a different customer', 'CUSTOMER_MISMATCH');
    }
    const customerId = line.customerId ?? invoice?.customerId ?? null;
    if (!customerId) {
      throw ApiError.badRequest('Each collection line needs a customer', 'CUSTOMER_REQUIRED');
    }

    const amount = round2(line.amount);
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

    total = round2(total + amount);
  }

  return tx.collectionVoucher.update({
    where: { id: voucher.id },
    data: { total },
    include: collectionInclude,
  });
}

interface BulkCollectionContext {
  box: CashBox;
  collectedAt: Date;
  number: string;
}

/**
 * Inserts a collection receipt (customers only, no invoice allocations) with a
 * constant number of queries regardless of the line count.
 */
async function createBulkCollectionTx(
  tx: Tx,
  input: CreateCollectionInput,
  context: BulkCollectionContext,
) {
  const { box, collectedAt, number } = context;

  if (input.lines.some((line) => !line.customerId)) {
    throw ApiError.badRequest('Each collection line needs a customer', 'CUSTOMER_REQUIRED');
  }

  const customerIds = [...new Set(input.lines.map((line) => line.customerId!))];
  const foundCustomers = await tx.customer.findMany({
    where: { id: { in: customerIds } },
    select: { id: true },
  });
  if (foundCustomers.length !== customerIds.length) {
    throw ApiError.badRequest('A customer on this receipt no longer exists', 'CUSTOMER_NOT_FOUND');
  }

  // Resolve every referenced cash box exactly once; most receipts only use the
  // header box, so the default branch stays a single read.
  const boxIds = [
    ...new Set(
      input.lines
        .map((line) => line.cashBoxId)
        .filter((id): id is string => Boolean(id)),
    ),
  ];
  const boxes = new Map<string, CashBox>([[box.id, box]]);
  for (const boxId of boxIds) {
    if (boxId !== box.id) boxes.set(boxId, await resolveCashBoxTx(tx, boxId));
  }

  const settings = await getSettings(tx);
  const numbers = await nextNumbers(
    tx,
    'payment',
    settings.paymentPrefix,
    input.lines.length,
    collectedAt,
    async (candidates) => {
      const rows = await tx.payment.findMany({
        where: { number: { in: candidates } },
        select: { number: true },
      });
      return new Set(rows.map((row) => row.number));
    },
    async (candidate) =>
      (await tx.payment.count({ where: { number: candidate } })) > 0,
  );

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

  const payments = input.lines.map((line, index) => {
    const amount = round2(line.amount);
    return {
      id: randomUUID(),
      number: numbers[index],
      customerId: line.customerId!,
      cashBoxId: line.cashBoxId ? boxes.get(line.cashBoxId)!.id : box.id,
      amount,
      lineNote: line.note ?? null,
      note: line.note ?? input.note ?? `Collection ${number}`,
    };
  });

  await tx.payment.createMany({
    data: payments.map((payment) => ({
      id: payment.id,
      number: payment.number,
      direction: 'INBOUND',
      customerId: payment.customerId,
      cashBoxId: payment.cashBoxId,
      collectionVoucherId: voucher.id,
      method: 'CASH',
      amount: payment.amount,
      reference: input.reference ?? number,
      note: payment.note,
      paidAt: collectedAt,
      userId: input.userId ?? null,
    })),
  });

  await postJournalBatch(
    tx,
    payments.map((payment) => ({
      memo: `Payment ${payment.number}`,
      reference: payment.number,
      sourceType: 'PAYMENT',
      sourceId: payment.id,
      userId: input.userId,
      entryDate: collectedAt,
      lines: [
        {
          accountCode: ACCOUNT.CASH,
          debit: payment.amount,
          description: `Funds received (${payment.number})`,
        },
        {
          accountCode: ACCOUNT.RECEIVABLE,
          credit: payment.amount,
          description: `Receipt (${payment.number})`,
        },
      ],
    })),
  );

  await tx.collectionLine.createMany({
    data: payments.map((payment) => ({
      id: randomUUID(),
      collectionVoucherId: voucher.id,
      customerId: payment.customerId,
      cashBoxId: payment.cashBoxId,
      amount: payment.amount,
      note: payment.lineNote,
    })),
  });

  // Keep the stored customer balance in step with the receipts. The bulk path
  // bypasses createPaymentTx, so it must refresh each affected account itself.
  for (const customerId of customerIds) {
    await recalcCustomerBalance(tx, customerId);
  }

  const total = round2(payments.reduce((sum, payment) => sum + payment.amount, 0));
  return tx.collectionVoucher.update({
    where: { id: voucher.id },
    data: { total },
    include: collectionInclude,
  });
}

export async function createCollection(input: CreateCollectionInput) {
  return prisma.$transaction((tx) => createCollectionTx(tx, input));
}

/**
 * Edits a collection receipt in place: the old payments are reversed (which
 * restores customer balances, cash boxes and journals) and the receipt is
 * rebuilt with the new header and lines under the same voucher number.
 */
export async function updateCollectionTx(
  tx: Tx,
  voucherId: string,
  input: Partial<CreateCollectionInput>,
) {
  const existing = await tx.collectionVoucher.findUnique({
    where: { id: voucherId },
    include: {
      payments: { select: { id: true, cancelledAt: true } },
      lines: true,
    },
  });
  if (!existing) throw ApiError.notFound('Collection receipt not found');
  if (existing.cancelledAt) {
    throw ApiError.conflict('A cancelled receipt cannot be edited', 'ALREADY_CANCELLED');
  }

  const lines = input.lines ??
    existing.lines.map((line) => ({
      customerId: line.customerId,
      invoiceId: line.invoiceId,
      cashBoxId: line.cashBoxId,
      amount: Number(line.amount),
      note: line.note,
    }));
  if (lines.length === 0) {
    throw ApiError.badRequest('A collection receipt needs at least one line', 'NO_LINES');
  }
  if (lines.some((line) => !(line.amount > 0))) {
    throw ApiError.badRequest('Every collection line needs a positive amount', 'INVALID_LINE');
  }

  for (const payment of existing.payments) {
    if (!payment.cancelledAt) await cancelPaymentTx(tx, payment.id, input.userId);
  }
  await tx.collectionLine.deleteMany({ where: { collectionVoucherId: voucherId } });

  const box = await resolveCashBoxTx(tx, input.cashBoxId ?? existing.cashBoxId);
  const collectedAt = input.collectedAt ?? existing.collectedAt;
  const salespersonId =
    input.salespersonId === undefined ? existing.salespersonId : input.salespersonId;
  if (salespersonId) {
    const salesperson = await tx.user.findUnique({ where: { id: salespersonId } });
    if (!salesperson) {
      throw ApiError.badRequest('Salesperson not found', 'SALESPERSON_NOT_FOUND');
    }
  }

  await tx.collectionVoucher.update({
    where: { id: voucherId },
    data: {
      cashBoxId: box.id,
      salespersonId,
      collectedAt,
      reference:
        input.reference === undefined ? existing.reference : input.reference,
      note: input.note === undefined ? existing.note : input.note,
      total: 0,
    },
  });

  let total = 0;
  for (const line of lines) {
    let invoice: { id: string; number: string; customerId: string | null } | null = null;
    if (line.invoiceId) {
      invoice = await tx.invoice.findUnique({
        where: { id: line.invoiceId },
        select: { id: true, number: true, customerId: true },
      });
      if (!invoice) throw ApiError.notFound('Invoice not found');
    }
    const customerId = line.customerId ?? invoice?.customerId ?? null;
    if (!customerId) {
      throw ApiError.badRequest('Each collection line needs a customer', 'CUSTOMER_REQUIRED');
    }
    if (
      line.customerId &&
      invoice?.customerId &&
      invoice.customerId !== line.customerId
    ) {
      throw ApiError.badRequest('The invoice belongs to a different customer', 'CUSTOMER_MISMATCH');
    }

    const amount = round2(line.amount);
    const lineBox = line.cashBoxId
      ? await resolveCashBoxTx(tx, line.cashBoxId)
      : box;
    await createPaymentTx(tx, {
      invoiceId: invoice?.id ?? null,
      customerId,
      amount,
      direction: 'INBOUND',
      method: 'CASH',
      paidAt: collectedAt,
      reference: input.reference === undefined ? existing.reference ?? existing.number : input.reference ?? existing.number,
      note: line.note ?? input.note ?? existing.note ?? `Collection ${existing.number}`,
      userId: input.userId,
      cashBoxId: lineBox.id,
      collectionVoucherId: voucherId,
    });
    await tx.collectionLine.create({
      data: {
        collectionVoucherId: voucherId,
        customerId,
        invoiceId: invoice?.id ?? null,
        cashBoxId: lineBox.id,
        amount,
        note: line.note ?? null,
      },
    });
    total = round2(total + amount);
  }

  return tx.collectionVoucher.update({
    where: { id: voucherId },
    data: { total },
    include: collectionInclude,
  });
}

export async function updateCollection(
  voucherId: string,
  input: Partial<CreateCollectionInput>,
) {
  return prisma.$transaction((tx) => updateCollectionTx(tx, voucherId, input));
}

export async function cancelCollectionTx(tx: Tx, voucherId: string, userId?: string) {
  const voucher = await tx.collectionVoucher.findUnique({
    where: { id: voucherId },
    include: { payments: { select: { id: true, cancelledAt: true } } },
  });
  if (!voucher) throw ApiError.notFound('Collection receipt not found');
  if (voucher.cancelledAt) throw ApiError.conflict('This receipt is already cancelled', 'ALREADY_CANCELLED');

  for (const payment of voucher.payments) {
    if (!payment.cancelledAt) await cancelPaymentTx(tx, payment.id, userId);
  }

  return tx.collectionVoucher.update({
    where: { id: voucher.id },
    data: { cancelledAt: new Date(), cancelledBy: userId ?? null },
    include: collectionInclude,
  });
}

export async function cancelCollection(voucherId: string, userId?: string) {
  return prisma.$transaction((tx) => cancelCollectionTx(tx, voucherId, userId));
}
