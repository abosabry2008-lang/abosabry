import { PaymentDirection, PaymentMethod, Prisma } from '@prisma/client';
import { ApiError } from '../../lib/api-error';
import { round2 } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { nextNumber } from '../../lib/sequence';
import { getSettings } from '../../lib/settings';
import { ACCOUNT, postJournal } from '../accounting/accounting.service';
import { recalcCustomerBalance } from '../invoices/invoices.service';

export const paymentInclude = {
  customer: { select: { id: true, name: true } },
  supplier: { select: { id: true, name: true } },
  invoice: { select: { id: true, number: true, total: true, balance: true, status: true } },
  currency: { select: { id: true, code: true, symbol: true } },
  user: { select: { id: true, name: true } },
} satisfies Prisma.PaymentInclude;

export interface CreatePaymentInput {
  direction?: PaymentDirection;
  invoiceId?: string | null;
  customerId?: string | null;
  supplierId?: string | null;
  currencyId?: string | null;
  method?: PaymentMethod;
  amount: number;
  reference?: string | null;
  note?: string | null;
  paidAt?: Date | null;
  userId?: string;
}

export async function createPaymentTx(tx: Tx, input: CreatePaymentInput) {
  if (input.amount <= 0) throw ApiError.badRequest('Payment amount must be greater than zero');

  const method: PaymentMethod = input.method ?? 'CASH';
  const cashAccount = method === 'CASH' ? ACCOUNT.CASH : ACCOUNT.BANK;
  const direction: PaymentDirection = input.direction ?? 'INBOUND';
  const paidAt = input.paidAt ?? new Date();
  const settings = await getSettings(tx);
  const number = await nextNumber(tx, 'payment', settings.paymentPrefix, paidAt);
  const amount = round2(input.amount);

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
        method,
        amount,
        reference: input.reference ?? null,
        note: input.note ?? null,
        paidAt,
        userId: input.userId ?? null,
      },
      include: paymentInclude,
    });

    await postJournal(tx, {
      memo: `Payment ${number} for invoice ${invoice.number}`,
      reference: number,
      sourceType: 'PAYMENT',
      sourceId: payment.id,
      userId: input.userId,
      entryDate: paidAt,
      lines: [
        { accountCode: cashAccount, debit: amount, description: `Payment received (${number})` },
        { accountCode: ACCOUNT.RECEIVABLE, credit: amount, description: `Invoice ${invoice.number}` },
      ],
    });

    if (invoice.customerId) await recalcCustomerBalance(tx, invoice.customerId);
    return payment;
  }

  if (input.supplierId && direction === 'OUTBOUND') {
    const payment = await tx.payment.create({
      data: {
        number,
        direction: 'OUTBOUND',
        supplierId: input.supplierId,
        currencyId: input.currencyId ?? null,
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

    await postJournal(tx, {
      memo: `Supplier payment ${number}`,
      reference: number,
      sourceType: 'PAYMENT',
      sourceId: payment.id,
      userId: input.userId,
      entryDate: paidAt,
      lines: [
        { accountCode: ACCOUNT.PAYABLE, debit: amount, description: `Payable settled (${number})` },
        { accountCode: cashAccount, credit: amount, description: `Payment made (${number})` },
      ],
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
      method,
      amount,
      reference: input.reference ?? null,
      note: input.note ?? null,
      paidAt,
      userId: input.userId ?? null,
    },
    include: paymentInclude,
  });

  await postJournal(tx, {
    memo: `Payment ${number}`,
    reference: number,
    sourceType: 'PAYMENT',
    sourceId: payment.id,
    userId: input.userId,
    entryDate: paidAt,
    lines:
      direction === 'INBOUND'
        ? [
            { accountCode: cashAccount, debit: amount, description: `Funds received (${number})` },
            { accountCode: ACCOUNT.RECEIVABLE, credit: amount, description: `On-account receipt (${number})` },
          ]
        : [
            { accountCode: ACCOUNT.PAYABLE, debit: amount, description: `On-account payment (${number})` },
            { accountCode: cashAccount, credit: amount, description: `Funds paid (${number})` },
          ],
  });

  return payment;
}

export async function createPayment(input: CreatePaymentInput) {
  return prisma.$transaction((tx) => createPaymentTx(tx, input));
}
