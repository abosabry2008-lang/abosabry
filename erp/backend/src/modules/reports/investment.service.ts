import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';

/** Inventory + cash + customer debt − supplier balances. */
export async function buildInvestmentEquation() {
  const [stock, products, boxes, paymentGroups, transfersOut, transfersIn, expenseGroups, customers, suppliers] =
    await Promise.all([
      prisma.stockLevel.groupBy({ by: ['productId'], _sum: { quantity: true } }),
      prisma.product.findMany({
        select: { id: true, name: true, sku: true, costPrice: true },
      }),
      prisma.cashBox.findMany({
        where: { active: true },
        select: { id: true, name: true, openingBalance: true },
      }),
      prisma.payment.groupBy({
        by: ['cashBoxId', 'direction'],
        where: { cashBoxId: { not: null }, cancelledAt: null },
        _sum: { amount: true },
      }),
      prisma.cashTransfer.groupBy({
        by: ['fromBoxId'],
        where: { cancelledAt: null },
        _sum: { amount: true },
      }),
      prisma.cashTransfer.groupBy({
        by: ['toBoxId'],
        where: { cancelledAt: null },
        _sum: { amount: true },
      }),
      prisma.expense.groupBy({
        by: ['cashBoxId'],
        where: { cashBoxId: { not: null }, cancelledAt: null },
        _sum: { amount: true },
      }),
      prisma.customer.findMany({
        select: { id: true, name: true, balance: true },
        orderBy: { balance: 'desc' },
      }),
      prisma.supplier.findMany({
        select: { id: true, name: true, balance: true },
        orderBy: { balance: 'desc' },
      }),
    ]);

  const productById = new Map(products.map((product) => [product.id, product]));
  const inventory = stock
    .map((level) => {
      const product = productById.get(level.productId);
      const quantity = Number(level._sum.quantity ?? 0);
      return {
        id: level.productId,
        name: product?.name ?? level.productId,
        sku: product?.sku ?? null,
        quantity,
        value: round2(quantity * Number(product?.costPrice ?? 0)),
      };
    })
    .filter((row) => row.quantity !== 0);

  const paymentIn = new Map<string, number>();
  const paymentOut = new Map<string, number>();
  for (const group of paymentGroups) {
    if (!group.cashBoxId) continue;
    const target = group.direction === 'INBOUND' ? paymentIn : paymentOut;
    target.set(group.cashBoxId, round2(Number(group._sum.amount ?? 0)));
  }
  const transferOut = new Map(
    transfersOut.map((row) => [row.fromBoxId, round2(Number(row._sum.amount ?? 0))]),
  );
  const transferIn = new Map(
    transfersIn.map((row) => [row.toBoxId, round2(Number(row._sum.amount ?? 0))]),
  );
  const expensesByBox = new Map(
    expenseGroups.map((row) => [row.cashBoxId!, round2(Number(row._sum.amount ?? 0))]),
  );
  const cash = boxes
    .map((box) => ({
      id: box.id,
      name: box.name,
      balance: round2(
        Number(box.openingBalance) +
          (paymentIn.get(box.id) ?? 0) -
          (paymentOut.get(box.id) ?? 0) +
          (transferIn.get(box.id) ?? 0) -
          (transferOut.get(box.id) ?? 0) -
          (expensesByBox.get(box.id) ?? 0),
      ),
    }))
    .filter((row) => row.balance !== 0);

  const customerRows = customers
    .map((customer) => ({
      id: customer.id,
      name: customer.name,
      balance: round2(Number(customer.balance)),
    }))
    .filter((row) => row.balance !== 0);
  const supplierRows = suppliers
    .map((supplier) => ({
      id: supplier.id,
      name: supplier.name,
      balance: round2(Number(supplier.balance)),
    }))
    .filter((row) => row.balance !== 0);

  const inventoryTotal = round2(inventory.reduce((sum, row) => sum + row.value, 0));
  const cashTotal = round2(cash.reduce((sum, row) => sum + row.balance, 0));
  const customersTotal = round2(customerRows.reduce((sum, row) => sum + row.balance, 0));
  const suppliersTotal = round2(supplierRows.reduce((sum, row) => sum + row.balance, 0));

  return {
    inventory: { total: inventoryTotal, rows: inventory },
    cash: { total: cashTotal, rows: cash },
    customers: { total: customersTotal, rows: customerRows },
    suppliers: { total: suppliersTotal, rows: supplierRows },
    net: round2(inventoryTotal + cashTotal + customersTotal - suppliersTotal),
  };
}
