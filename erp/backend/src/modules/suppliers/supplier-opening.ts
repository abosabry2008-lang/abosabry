import { ApiError } from '../../lib/api-error';
import { round2 } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { ACCOUNT, postJournal, reverseJournalBySource } from '../accounting/accounting.service';

/**
 * A supplier's opening balance comes from two places:
 *  - the supplier form (journal `OPENING_SUPPLIER`, one entry, corrected by
 *    reversing it and posting a new one), and
 *  - the opening-balances screen (`OpeningBalance.details.suppliers`).
 * The admin edits the total; only the form-owned part is adjusted.
 */

/** Amount of the latest supplier-form opening entry that has not been reversed. */
async function formOpeningAmount(tx: Tx, supplierId: string): Promise<number> {
  const entry = await tx.journalEntry.findFirst({
    where: { sourceType: 'OPENING_SUPPLIER', sourceId: supplierId },
    orderBy: { createdAt: 'desc' },
    include: { lines: { include: { account: { select: { code: true } } } } },
  });
  if (!entry) return 0;
  const reversed = await tx.journalEntry.findFirst({
    where: {
      sourceType: 'OPENING_SUPPLIER_REVERSAL',
      sourceId: supplierId,
      createdAt: { gt: entry.createdAt },
    },
    select: { id: true },
  });
  if (reversed) return 0;
  return round2(
    entry.lines
      .filter((line) => line.account.code === ACCOUNT.PAYABLE)
      .reduce((sum, line) => sum + Number(line.credit) - Number(line.debit), 0),
  );
}

/** Amount recorded for this supplier on the opening-balances screen. */
async function openingBalanceScreenAmount(tx: Tx, supplierId: string): Promise<number> {
  const rows = await tx.openingBalance.findMany({
    where: { cancelledAt: null },
    select: { details: true },
  });
  let total = 0;
  for (const row of rows) {
    const details = (row.details ?? {}) as {
      suppliers?: { supplierId: string; amount: number }[];
    };
    for (const line of details.suppliers ?? []) {
      if (line.supplierId === supplierId) total += Number(line.amount ?? 0);
    }
  }
  return round2(total);
}

/** The supplier's total opening balance as the admin sees it. */
export async function getSupplierOpeningBalance(supplierId: string): Promise<number> {
  return prisma.$transaction(async (tx) =>
    round2((await formOpeningAmount(tx, supplierId)) + (await openingBalanceScreenAmount(tx, supplierId))),
  );
}

/**
 * Sets the supplier's total opening balance. The difference against the current
 * form-owned entry is posted as a reversal plus a new entry, and the supplier
 * balance moves by the same difference.
 */
export async function setSupplierOpeningBalance(
  tx: Tx,
  supplierId: string,
  total: number,
  userId?: string,
): Promise<void> {
  const supplier = await tx.supplier.findUnique({
    where: { id: supplierId },
    select: { id: true, name: true },
  });
  if (!supplier) throw ApiError.notFound('Supplier not found', 'SUPPLIER_NOT_FOUND');

  const fromScreen = await openingBalanceScreenAmount(tx, supplierId);
  const current = await formOpeningAmount(tx, supplierId);
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
      sourceType: 'OPENING_SUPPLIER',
      sourceId: supplierId,
      reversalSourceType: 'OPENING_SUPPLIER_REVERSAL',
      memo: `Opening balance corrected for supplier ${supplier.name}`,
      userId,
    });
    await tx.supplier.update({
      where: { id: supplierId },
      data: { balance: { decrement: current } },
    });
  }

  if (next > 0) {
    await tx.supplier.update({
      where: { id: supplierId },
      data: { balance: { increment: next } },
    });
    await postJournal(tx, {
      memo: `Opening balance for supplier ${supplier.name}`,
      reference: `OB-SUPP-${supplierId.slice(-6).toUpperCase()}`,
      sourceType: 'OPENING_SUPPLIER',
      sourceId: supplierId,
      userId,
      lines: [
        { accountCode: ACCOUNT.EQUITY, debit: next, description: 'Opening capital' },
        { accountCode: ACCOUNT.PAYABLE, credit: next, description: 'Opening payable' },
      ],
    });
  }
}
