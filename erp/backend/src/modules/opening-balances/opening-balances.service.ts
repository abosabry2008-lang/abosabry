import { Prisma } from '@prisma/client';
import { ApiError } from '../../lib/api-error';
import { round2 } from '../../lib/money';
import { prisma, type Tx } from '../../lib/prisma';
import { nextNumber } from '../../lib/sequence';
import { getSettings } from '../../lib/settings';
import { ACCOUNT, postJournal, reverseJournalBySource } from '../accounting/accounting.service';
import { applyMovement, resolveLocation } from '../inventory/inventory.service';

export const openingBalanceInclude = {
  user: { select: { id: true, name: true } },
} satisfies Prisma.OpeningBalanceInclude;

export interface OpeningCustomerInput {
  customerId: string;
  /** ما لنا على العميل (مدين). */
  amount: number;
}

export interface OpeningSupplierInput {
  supplierId: string;
  /** ما علينا للمورد (دائن). */
  amount: number;
}

export interface OpeningInventoryInput {
  warehouseId: string;
  productId: string;
  quantity: number;
  unitCost: number;
}

export interface CreateOpeningBalanceInput {
  asOfDate?: Date;
  note?: string;
  userId?: string;
  customers?: OpeningCustomerInput[];
  suppliers?: OpeningSupplierInput[];
  inventory?: OpeningInventoryInput[];
}

/**
 * Creates an opening-balance entry (مديونية سابقة / قيد رأس المال).
 *
 * Single balanced journal:
 *   Dr Accounts Receivable      (customer debts)
 *   Dr Inventory                (stock valuation)
 *   Cr Accounts Payable         (supplier debts)
 *   Cr Owner's Equity           (the balancing capital figure)
 *
 * It also sets each partner's `balance` and raises the opening stock
 * movements, all inside one transaction.
 */
export async function createOpeningBalanceTx(
  tx: Tx,
  input: CreateOpeningBalanceInput,
) {
  const customers = (input.customers ?? []).filter((row) => round2(row.amount) > 0);
  const suppliers = (input.suppliers ?? []).filter((row) => round2(row.amount) > 0);
  const inventory = (input.inventory ?? []).filter(
    (row) => row.quantity > 0 && round2(row.unitCost) >= 0,
  );

  if (customers.length === 0 && suppliers.length === 0 && inventory.length === 0) {
    throw ApiError.badRequest(
      'Add at least one opening balance line',
      'EMPTY_OPENING_BALANCE',
    );
  }

  const customerTotal = round2(customers.reduce((sum, row) => sum + row.amount, 0));
  const supplierTotal = round2(suppliers.reduce((sum, row) => sum + row.amount, 0));
  const inventoryTotal = round2(
    inventory.reduce((sum, row) => sum + row.quantity * row.unitCost, 0),
  );

  // Guard: a partner may only appear once and must exist.
  const customerIds = customers.map((row) => row.customerId);
  const supplierIds = suppliers.map((row) => row.supplierId);
  if (new Set(customerIds).size !== customerIds.length) {
    throw ApiError.badRequest('Duplicate customer in opening balance', 'DUPLICATE_PARTNER');
  }
  if (new Set(supplierIds).size !== supplierIds.length) {
    throw ApiError.badRequest('Duplicate supplier in opening balance', 'DUPLICATE_PARTNER');
  }

  const settings = await getSettings(tx);
  const asOfDate = input.asOfDate ?? new Date();
  const number = await nextNumber(tx, 'openingBalance', settings.openingBalancePrefix, asOfDate);

  // Apply partner balances.
  for (const row of customers) {
    const customer = await tx.customer.findUnique({ where: { id: row.customerId } });
    if (!customer) throw ApiError.badRequest('Customer not found', 'CUSTOMER_NOT_FOUND');
    await tx.customer.update({
      where: { id: row.customerId },
      data: { balance: { increment: round2(row.amount) } },
    });
  }
  for (const row of suppliers) {
    const supplier = await tx.supplier.findUnique({ where: { id: row.supplierId } });
    if (!supplier) throw ApiError.badRequest('Supplier not found', 'SUPPLIER_NOT_FOUND');
    await tx.supplier.update({
      where: { id: row.supplierId },
      data: { balance: { increment: round2(row.amount) } },
    });
  }

  // Raise opening stock movements.
  for (const row of inventory) {
    const location = await resolveLocation(tx, row.warehouseId);
    await applyMovement(tx, {
      type: 'OPENING',
      productId: row.productId,
      locationId: location.id,
      quantity: row.quantity,
      unitCost: round2(row.unitCost),
      reference: number,
      note: `Opening stock (${number})`,
      userId: input.userId,
    });
  }

  const entry = await tx.openingBalance.create({
    data: {
      number,
      asOfDate,
      note: input.note,
      userId: input.userId ?? null,
      customerTotal,
      supplierTotal,
      inventoryTotal,
      details: {
        customers: customers.map((row) => ({
          customerId: row.customerId,
          amount: round2(row.amount),
        })),
        suppliers: suppliers.map((row) => ({
          supplierId: row.supplierId,
          amount: round2(row.amount),
        })),
      },
    },
    include: openingBalanceInclude,
  });

  // Post the balancing capital entry.
  const lines: { accountCode: string; debit?: number; credit?: number; description?: string }[] = [];
  if (customerTotal > 0) {
    lines.push({
      accountCode: ACCOUNT.RECEIVABLE,
      debit: customerTotal,
      description: `Opening receivable (${number})`,
    });
  }
  if (inventoryTotal > 0) {
    lines.push({
      accountCode: ACCOUNT.INVENTORY,
      debit: inventoryTotal,
      description: `Opening inventory (${number})`,
    });
  }
  if (supplierTotal > 0) {
    lines.push({
      accountCode: ACCOUNT.PAYABLE,
      credit: supplierTotal,
      description: `Opening payable (${number})`,
    });
  }
  const equity = round2(customerTotal + inventoryTotal - supplierTotal);
  lines.push({
    accountCode: ACCOUNT.EQUITY,
    debit: equity < 0 ? -equity : undefined,
    credit: equity > 0 ? equity : undefined,
    description: `Opening capital (${number})`,
  });

  await postJournal(tx, {
    memo: `Opening balances (${number})`,
    reference: number,
    sourceType: 'OPENING_BALANCE',
    sourceId: entry.id,
    userId: input.userId,
    entryDate: asOfDate,
    lines,
  });

  return entry;
}

export async function createOpeningBalance(input: CreateOpeningBalanceInput) {
  return prisma.$transaction((tx) => createOpeningBalanceTx(tx, input));
}

/**
 * Cancels an opening-balance entry: reverses the journal, the partner
 * balances and the opening stock movements.
 */
export async function cancelOpeningBalance(id: string, userId?: string) {
  return prisma.$transaction(async (tx) => {
    const entry = await tx.openingBalance.findUnique({
      where: { id },
      include: {
        user: { select: { id: true, name: true } },
      },
    });
    if (!entry) throw ApiError.notFound('Opening balance not found', 'OPENING_BALANCE_NOT_FOUND');
    if (entry.cancelledAt) {
      throw ApiError.conflict('This opening balance is already cancelled', 'ALREADY_CANCELLED');
    }

    // Reverse stock movements recorded for this entry.
    const movements = await tx.stockMovement.findMany({
      where: { type: 'OPENING', reference: entry.number },
    });
    for (const movement of movements) {
      await applyMovement(tx, {
        type: 'ADJUSTMENT',
        productId: movement.productId,
        locationId: movement.locationId,
        quantity: -movement.quantity,
        unitCost: Number(movement.unitCost ?? 0),
        reference: entry.number,
        note: `Opening stock reversed (${entry.number})`,
        userId,
      });
    }

    // Reverse any partner balances applied for this entry.
    const details = (entry.details ?? {}) as {
      customers?: { customerId: string; amount: number }[];
      suppliers?: { supplierId: string; amount: number }[];
    };
    for (const row of details.customers ?? []) {
      await tx.customer.update({
        where: { id: row.customerId },
        data: { balance: { decrement: round2(row.amount) } },
      });
    }
    for (const row of details.suppliers ?? []) {
      await tx.supplier.update({
        where: { id: row.supplierId },
        data: { balance: { decrement: round2(row.amount) } },
      });
    }

    await reverseJournalBySource(tx, {
      sourceType: 'OPENING_BALANCE',
      sourceId: entry.id,
      reversalSourceType: 'OPENING_BALANCE_CANCEL',
      memo: `Opening balances reversed (${entry.number})`,
      reference: entry.number,
      userId,
    });

    return tx.openingBalance.update({
      where: { id },
      data: { cancelledAt: new Date(), cancelledBy: userId ?? null },
      include: openingBalanceInclude,
    });
  });
}

export async function listOpeningBalances() {
  return prisma.openingBalance.findMany({
    include: openingBalanceInclude,
    orderBy: [{ asOfDate: 'desc' }, { createdAt: 'desc' }],
  });
}
