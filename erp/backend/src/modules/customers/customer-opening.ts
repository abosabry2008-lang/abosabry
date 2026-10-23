import { ApiError } from '../../lib/api-error';
import { round2 } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { ACCOUNT, postJournal, reverseJournalBySource } from '../accounting/accounting.service';

/**
 * Customer opening balances are posted as `OPENING_CUSTOMER`. The total opening
 * balance an admin sees is that single entry, adjusted for what was already
 * recorded on the opening-balances screen.
 */

async function formOpeningAmount(tx: Tx, customerId: string): Promise<number> {
  const entry = await tx.journalEntry.findFirst({
    where: { sourceType: 'OPENING_CUSTOMER', sourceId: customerId },
    orderBy: { createdAt: 'desc' },
    include: { lines: { include: { account: { select: { code: true } } } } },
  });
  if (!entry) return 0;
  const reversed = await tx.journalEntry.findFirst({
    where: {
      sourceType: 'OPENING_CUSTOMER_REVERSAL',
      sourceId: customerId,
      createdAt: { gt: entry.createdAt },
    },
    select: { id: true },
  });
  if (reversed) return 0;
  return round2(
    entry.lines
      .filter((line) => line.account.code === ACCOUNT.RECEIVABLE)
      .reduce((sum, line) => sum + Number(line.debit) - Number(line.credit), 0),
  );
}

async function openingBalanceScreenAmount(tx: Tx, customerId: string): Promise<number> {
  const rows = await tx.openingBalance.findMany({
    where: { cancelledAt: null },
    select: { details: true },
  });
  let total = 0;
  for (const row of rows) {
    const details = (row.details ?? {}) as {
      customers?: { customerId: string; amount: number }[];
    };
    for (const line of details.customers ?? []) {
      if (line.customerId === customerId) total += Number(line.amount ?? 0);
    }
  }
  return round2(total);
}

export async function getCustomerOpeningBalance(customerId: string): Promise<number> {
  return prisma.$transaction(async (tx) =>
    round2((await formOpeningAmount(tx, customerId)) + (await openingBalanceScreenAmount(tx, customerId))),
  );
}

export async function setCustomerOpeningBalance(
  tx: Tx,
  customerId: string,
  total: number,
  userId?: string,
): Promise<void> {
  const customer = await tx.customer.findUnique({
    where: { id: customerId },
    select: { id: true, name: true },
  });
  if (!customer) throw ApiError.notFound('Customer not found', 'CUSTOMER_NOT_FOUND');

  const fromScreen = await openingBalanceScreenAmount(tx, customerId);
  const current = await formOpeningAmount(tx, customerId);
  const next = round2(round2(total) - fromScreen);
  if (next < 0) {
    throw ApiError.badRequest(
      'The opening balance is lower than the amount already recorded on the opening-balances screen',
      'OPENING_BALANCE_TOO_LOW',
    );
  }
  if (next === current) return;

  if (current > 0) {
    await reverseJournalBySource(tx, {
      sourceType: 'OPENING_CUSTOMER',
      sourceId: customerId,
      reversalSourceType: 'OPENING_CUSTOMER_REVERSAL',
      memo: `Opening balance corrected for customer ${customer.name}`,
      userId,
    });
    await tx.customer.update({
      where: { id: customerId },
      data: { balance: { decrement: current } },
    });
  }

  if (next > 0) {
    await tx.customer.update({
      where: { id: customerId },
      data: { balance: { increment: next } },
    });
    await postJournal(tx, {
      memo: `Opening balance for customer ${customer.name}`,
      reference: `OB-CUST-${customerId.slice(-6).toUpperCase()}`,
      sourceType: 'OPENING_CUSTOMER',
      sourceId: customerId,
      userId,
      lines: [
        { accountCode: ACCOUNT.RECEIVABLE, debit: next, description: 'Opening receivable' },
        { accountCode: ACCOUNT.EQUITY, credit: next, description: 'Opening capital' },
      ],
    });
  }
}
