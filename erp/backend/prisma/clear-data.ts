/**
 * Clears the trading data so the shop can start entering real data:
 * products, customers, suppliers and everything that hangs off them
 * (invoices, orders, payments, stock movements, settlements, journals).
 *
 * Kept intact: users, settings, chart of accounts, cash boxes, warehouses,
 * categories and currencies.
 *
 * Run:  npx ts-node prisma/clear-data.ts
 */
import { prisma } from '../src/lib/prisma';

async function main(): Promise<void> {
  console.log('Clearing trading data (products / customers / suppliers)...');

  // Order matters: children before parents.
  await prisma.journalLine.deleteMany();
  await prisma.journalEntry.deleteMany();

  await prisma.collectionLine.deleteMany();
  await prisma.collectionVoucher.deleteMany();

  await prisma.payment.deleteMany();

  await prisma.invoiceLine.deleteMany();
  await prisma.invoice.deleteMany();

  await prisma.salesOrderLine.deleteMany();
  await prisma.salesOrder.deleteMany();

  await prisma.purchaseOrderLine.deleteMany();
  await prisma.purchaseOrder.deleteMany();

  await prisma.returnOrderLine.deleteMany();
  await prisma.returnOrder.deleteMany();

  await prisma.openingBalance.deleteMany();
  await prisma.accountSettlement.deleteMany();

  await prisma.stockMovement.deleteMany();
  await prisma.stockLevel.deleteMany();

  await prisma.product.deleteMany();
  await prisma.supplier.deleteMany();
  await prisma.customer.deleteMany();

  // Reset the counters so new documents start from 1 again.
  await prisma.sequence.deleteMany();

  const counts = {
    products: await prisma.product.count(),
    customers: await prisma.customer.count(),
    suppliers: await prisma.supplier.count(),
  };
  console.log('Done. Remaining:', counts);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
