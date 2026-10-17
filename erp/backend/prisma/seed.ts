/**
 * Seeds a demo dataset. Run after the schema is applied:
 *   npm run prisma:push   (or npm run prisma:migrate)
 *   npm run seed
 *
 * WARNING: this clears existing data.
 */
import { hashPassword } from '../src/lib/password';
import { prisma } from '../src/lib/prisma';
import { getSettings } from '../src/lib/settings';
import { ensureDefaultAccounts } from '../src/modules/accounting/accounting.service';
import { createInvoice, issueInvoice } from '../src/modules/invoices/invoices.service';
import { receiveStock } from '../src/modules/inventory/inventory.service';
import { createPayment } from '../src/modules/payments/payments.service';
import { createPurchaseOrder, receivePurchaseOrder } from '../src/modules/purchasing/purchasing.service';
import { confirmSalesOrder, createSalesOrder, fulfillSalesOrder } from '../src/modules/sales/sales.service';

async function wipe(): Promise<void> {
  await prisma.journalLine.deleteMany();
  await prisma.journalEntry.deleteMany();
  await prisma.account.deleteMany();
  await prisma.payment.deleteMany();
  await prisma.invoiceLine.deleteMany();
  await prisma.invoice.deleteMany();
  await prisma.salesOrderLine.deleteMany();
  await prisma.salesOrder.deleteMany();
  await prisma.purchaseOrderLine.deleteMany();
  await prisma.purchaseOrder.deleteMany();
  await prisma.stockMovement.deleteMany();
  await prisma.stockLevel.deleteMany();
  await prisma.location.deleteMany();
  await prisma.warehouse.deleteMany();
  await prisma.product.deleteMany();
  await prisma.category.deleteMany();
  await prisma.supplier.deleteMany();
  await prisma.customer.deleteMany();
  await prisma.refreshToken.deleteMany();
  await prisma.user.deleteMany();
  await prisma.currency.deleteMany();
  await prisma.sequence.deleteMany();
  await prisma.setting.deleteMany();
}

async function main(): Promise<void> {
  console.log('Clearing existing data...');
  await wipe();

  console.log('Creating settings and chart of accounts...');
  await getSettings();
  await prisma.setting.update({
    where: { id: 1 },
    data: {
      companyName: 'Acme Trading Co.',
      companyEmail: 'hello@acme.example',
      companyPhone: '+1 555 0100',
      companyAddress: '12 Market Street, Springfield',
      baseCurrencyCode: 'USD',
      defaultTaxRate: 5,
    },
  });
  await prisma.$transaction((tx) => ensureDefaultAccounts(tx));

  console.log('Creating currencies...');
  await prisma.currency.createMany({
    data: [
      { code: 'USD', name: 'US Dollar', symbol: '$', exchangeRate: 1, isBase: true },
      { code: 'EUR', name: 'Euro', symbol: '\u20ac', exchangeRate: 0.92 },
      { code: 'GBP', name: 'British Pound', symbol: '\u00a3', exchangeRate: 0.79 },
      { code: 'AED', name: 'UAE Dirham', symbol: 'AED', exchangeRate: 3.67 },
      { code: 'EGP', name: 'Egyptian Pound', symbol: 'EGP', exchangeRate: 30.85 },
    ],
  });
  const usd = await prisma.currency.findUniqueOrThrow({ where: { code: 'USD' } });

  console.log('Creating users...');
  const password = await hashPassword('Password123');
  await prisma.user.createMany({
    data: [
      { email: 'admin@erp.local', name: 'Ada Admin', role: 'ADMIN', passwordHash: password },
      { email: 'manager@erp.local', name: 'Mona Manager', role: 'MANAGER', passwordHash: password },
      { email: 'cashier@erp.local', name: 'Carl Cashier', role: 'CASHIER', passwordHash: password },
      { email: 'warehouse@erp.local', name: 'Wendy Warehouse', role: 'WAREHOUSE', passwordHash: password },
      { email: 'accountant@erp.local', name: 'Alan Accountant', role: 'ACCOUNTANT', passwordHash: password },
    ],
  });
  const admin = await prisma.user.findUniqueOrThrow({ where: { email: 'admin@erp.local' } });

  console.log('Creating catalogue...');
  const [beverages, electronics, stationery, groceries] = await Promise.all([
    prisma.category.create({ data: { name: 'Beverages', description: 'Drinks and juices' } }),
    prisma.category.create({ data: { name: 'Electronics', description: 'Devices and accessories' } }),
    prisma.category.create({ data: { name: 'Stationery', description: 'Office supplies' } }),
    prisma.category.create({ data: { name: 'Groceries', description: 'Everyday food items' } }),
  ]);

  const products = await Promise.all([
    prisma.product.create({ data: { sku: 'BEV-001', barcode: '1000000000017', name: 'Orange Juice 1L', categoryId: beverages.id, currencyId: usd.id, unit: 'btl', costPrice: 1.2, salePrice: 2.5, taxRate: 5, reorderLevel: 20 } }),
    prisma.product.create({ data: { sku: 'BEV-002', barcode: '1000000000024', name: 'Still Water 500ml', categoryId: beverages.id, currencyId: usd.id, unit: 'btl', costPrice: 0.3, salePrice: 0.9, taxRate: 5, reorderLevel: 48 } }),
    prisma.product.create({ data: { sku: 'BEV-003', barcode: '1000000000031', name: 'Cola 330ml Can', categoryId: beverages.id, currencyId: usd.id, unit: 'can', costPrice: 0.45, salePrice: 1.1, taxRate: 5, reorderLevel: 60 } }),
    prisma.product.create({ data: { sku: 'ELE-001', barcode: '1000000000048', name: 'USB-C Cable 1m', categoryId: electronics.id, currencyId: usd.id, unit: 'pc', costPrice: 2.1, salePrice: 6.99, taxRate: 5, reorderLevel: 15 } }),
    prisma.product.create({ data: { sku: 'ELE-002', barcode: '1000000000055', name: 'Wireless Mouse', categoryId: electronics.id, currencyId: usd.id, unit: 'pc', costPrice: 6.5, salePrice: 15.99, taxRate: 5, reorderLevel: 10 } }),
    prisma.product.create({ data: { sku: 'ELE-003', barcode: '1000000000062', name: 'Bluetooth Speaker', categoryId: electronics.id, currencyId: usd.id, unit: 'pc', costPrice: 12, salePrice: 29.99, taxRate: 5, reorderLevel: 8 } }),
    prisma.product.create({ data: { sku: 'STA-001', barcode: '1000000000079', name: 'A4 Notebook', categoryId: stationery.id, currencyId: usd.id, unit: 'pc', costPrice: 0.8, salePrice: 2.2, taxRate: 5, reorderLevel: 25 } }),
    prisma.product.create({ data: { sku: 'STA-002', barcode: '1000000000086', name: 'Ballpoint Pen (Blue)', categoryId: stationery.id, currencyId: usd.id, unit: 'pc', costPrice: 0.15, salePrice: 0.6, taxRate: 5, reorderLevel: 100 } }),
    prisma.product.create({ data: { sku: 'GRO-001', barcode: '1000000000093', name: 'Basmati Rice 5kg', categoryId: groceries.id, currencyId: usd.id, unit: 'bag', costPrice: 6.4, salePrice: 9.5, taxRate: 0, reorderLevel: 12 } }),
    prisma.product.create({ data: { sku: 'GRO-002', barcode: '1000000000109', name: 'Olive Oil 1L', categoryId: groceries.id, currencyId: usd.id, unit: 'btl', costPrice: 4.2, salePrice: 7.75, taxRate: 0, reorderLevel: 10 } }),
    prisma.product.create({ data: { sku: 'GRO-003', barcode: '1000000000116', name: 'Instant Coffee 200g', categoryId: groceries.id, currencyId: usd.id, unit: 'jar', costPrice: 3.1, salePrice: 5.9, taxRate: 0, reorderLevel: 18 } }),
  ]);

  console.log('Creating warehouses and locations...');
  const mainWarehouse = await prisma.warehouse.create({
    data: { code: 'MAIN', name: 'Main Warehouse', address: '12 Market Street, Springfield', phone: '+1 555 0100' },
  });
  const storeTwo = await prisma.warehouse.create({
    data: { code: 'STORE2', name: 'Second Store', address: '88 River Road, Shelbyville' },
  });
  const [mainA, mainB] = await Promise.all([
    prisma.location.create({ data: { warehouseId: mainWarehouse.id, code: 'A1', name: 'Aisle 1' } }),
    prisma.location.create({ data: { warehouseId: mainWarehouse.id, code: 'B1', name: 'Aisle 2' } }),
  ]);
  await prisma.location.create({ data: { warehouseId: storeTwo.id, code: 'MAIN', name: 'Shop Floor' } });

  console.log('Creating suppliers and customers...');
  const [supplierA, supplierB] = await Promise.all([
    prisma.supplier.create({ data: { name: 'Global Beverages Ltd', contact: 'Sam Seller', email: 'sales@globalbev.example', phone: '+1 555 0200', paymentTermDays: 30 } }),
    prisma.supplier.create({ data: { name: 'TechSource Inc.', contact: 'Tina Trader', email: 'orders@techsource.example', phone: '+1 555 0300', paymentTermDays: 45 } }),
  ]);
  await prisma.customer.create({ data: { name: 'Walk-in Customer', email: null, creditLimit: 0 } });
  const [customerA, customerB] = await Promise.all([
    prisma.customer.create({ data: { name: 'Blue Cafe', email: 'buyer@bluecafe.example', phone: '+1 555 0400', address: '5 High Street', creditLimit: 2000 } }),
    prisma.customer.create({ data: { name: 'Corner Store', email: 'owner@cornerstore.example', phone: '+1 555 0500', address: '9 Oak Avenue', creditLimit: 5000 } }),
  ]);

  console.log('Loading opening stock...');
  const opening: [string, string, number][] = [
    [products[0].id, mainA.id, 60],
    [products[1].id, mainA.id, 120],
    [products[2].id, mainA.id, 90],
    [products[3].id, mainB.id, 25],
    [products[4].id, mainB.id, 18],
    [products[5].id, mainB.id, 6],
    [products[6].id, mainA.id, 40],
    [products[7].id, mainA.id, 150],
    [products[8].id, mainB.id, 15],
    [products[9].id, mainB.id, 8],
    [products[10].id, mainB.id, 22],
  ];
  for (const [productId, locationId, quantity] of opening) {
    await receiveStock({ productId, locationId, quantity, reference: 'OPENING', userId: admin.id });
  }

  console.log('Creating a purchase order and receiving it...');
  const po = await createPurchaseOrder({
    supplierId: supplierA.id,
    warehouseId: mainWarehouse.id,
    currencyId: usd.id,
    notes: 'Weekly beverage restock',
    userId: admin.id,
    lines: [
      { productId: products[0].id, quantity: 48, unitCost: 1.15, taxRate: 5 },
      { productId: products[2].id, quantity: 96, unitCost: 0.42, taxRate: 5 },
    ],
  });
  await receivePurchaseOrder(po.id, { userId: admin.id });

  console.log('Creating a sales order, invoice and payment...');
  const order = await createSalesOrder({
    customerId: customerA.id,
    warehouseId: mainWarehouse.id,
    currencyId: usd.id,
    notes: 'Wholesale order',
    userId: admin.id,
    lines: [
      { productId: products[0].id, quantity: 12 },
      { productId: products[2].id, quantity: 24 },
      { productId: products[7].id, quantity: 50, discount: 2 },
    ],
  });
  await confirmSalesOrder(order.id);
  await fulfillSalesOrder(order.id, { userId: admin.id });

  const invoice = await createInvoice({ salesOrderId: order.id, userId: admin.id });
  const issued = await issueInvoice(invoice.id, admin.id);
  await createPayment({
    invoiceId: issued.id,
    amount: 50,
    method: 'BANK_TRANSFER',
    reference: 'WIRE-1001',
    userId: admin.id,
  });

  const secondOrder = await createSalesOrder({
    customerId: customerB.id,
    warehouseId: mainWarehouse.id,
    userId: admin.id,
    lines: [
      { productId: products[3].id, quantity: 5 },
      { productId: products[4].id, quantity: 3 },
    ],
  });
  await confirmSalesOrder(secondOrder.id);
  await fulfillSalesOrder(secondOrder.id, { userId: admin.id });

  console.log('\nSeed complete.\n');
  console.log('Sign in with any of these accounts (password: Password123):');
  console.log('  admin@erp.local       (ADMIN - full access)');
  console.log('  manager@erp.local     (MANAGER)');
  console.log('  cashier@erp.local     (CASHIER - POS)');
  console.log('  warehouse@erp.local   (WAREHOUSE - stock)');
  console.log('  accountant@erp.local  (ACCOUNTANT - ledger)');
}

main()
  .then(async () => {
    await prisma.$disconnect();
  })
  .catch(async (error) => {
    console.error(error);
    await prisma.$disconnect();
    process.exit(1);
  });
