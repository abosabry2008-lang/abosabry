import ExcelJS from 'exceljs';
import { prisma } from '../../lib/prisma';
import { dayKey } from './reports.service';

// ---------------------------------------------------------------------------
// Full data backup (نسخة احتياطية كاملة) — one workbook, one sheet per table.
// ---------------------------------------------------------------------------
//
// The backup is intentionally exhaustive: every business record, plus the
// derived balances the user cares about (receivables, payables, stock value and
// quantity). It is produced as a real .xlsx workbook.

type Column = { header: string; key: string; width?: number; money?: boolean };

interface BackupSheet {
  name: string;
  columns: Column[];
  rows: Record<string, unknown>[];
  totals?: Record<string, unknown>;
}

/** Formats a Date or ISO string as `YYYY-MM-DD HH:mm`. */
function stamp(value: unknown): string {
  if (value === null || value === undefined || value === '') return '';
  const date = value instanceof Date ? value : new Date(String(value));
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toISOString().replace('T', ' ').slice(0, 16);
}

function dateOnly(value: unknown): string {
  if (value === null || value === undefined || value === '') return '';
  const date = value instanceof Date ? value : new Date(String(value));
  if (Number.isNaN(date.getTime())) return String(value);
  return dayKey(date);
}

function n(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

/** Builds and serialises the whole backup workbook. */
export async function buildBackupWorkbook(): Promise<Buffer> {
  const sheets = await collectBackupSheets();

  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'ERP';
  workbook.created = new Date();

  for (const sheet of sheets) {
    const worksheet = workbook.addWorksheet(sheet.name.slice(0, 31), {
      views: [{ state: 'frozen', ySplit: 1 }],
    });

    worksheet.columns = sheet.columns.map((column) => ({
      header: column.header,
      key: column.key,
      width: column.width ?? 18,
    }));

    worksheet.getRow(1).font = { bold: true };
    worksheet.getRow(1).fill = {
      type: 'pattern',
      pattern: 'solid',
      fgColor: { argb: 'FFE2E8F0' },
    };

    for (const row of sheet.rows) {
      const added = worksheet.addRow(row);
      sheet.columns.forEach((column, index) => {
        if (column.money) added.getCell(index + 1).numFmt = '#,##0.00';
      });
    }

    if (sheet.totals) {
      const added = worksheet.addRow(sheet.totals);
      added.font = { bold: true };
      sheet.columns.forEach((column, index) => {
        if (column.money) added.getCell(index + 1).numFmt = '#,##0.00';
      });
    }
  }

  const arrayBuffer = await workbook.xlsx.writeBuffer();
  return Buffer.from(arrayBuffer);
}

/** Reads every dataset needed for the backup in one place. */
async function collectBackupSheets(): Promise<BackupSheet[]> {
  const [
    settings,
    customers,
    suppliers,
    products,
    warehouses,
    locations,
    stockLevels,
    cashBoxes,
    salesOrders,
    salesOrderLines,
    invoices,
    invoiceLines,
    purchaseOrders,
    purchaseOrderLines,
    payments,
    collectionVouchers,
    collectionLines,
    cashTransfers,
    journalEntries,
    journalLines,
    stockMovements,
  ] = await Promise.all([
    prismaSetting(),
    prismaCustomer(),
    prismaSupplier(),
    prismaProduct(),
    prismaWarehouse(),
    prismaLocation(),
    prismaStockLevel(),
    prismaCashBox(),
    prismaSalesOrder(),
    prismaSalesOrderLine(),
    prismaInvoice(),
    prismaInvoiceLine(),
    prismaPurchaseOrder(),
    prismaPurchaseOrderLine(),
    prismaPayment(),
    prismaCollectionVoucher(),
    prismaCollectionLine(),
    prismaCashTransfer(),
    prismaJournalEntry(),
    prismaJournalLine(),
    prismaStockMovement(),
  ]);

  return [
    settings,
    customers,
    suppliers,
    products,
    warehouses,
    locations,
    stockLevels,
    cashBoxes,
    salesOrders,
    salesOrderLines,
    invoices,
    invoiceLines,
    purchaseOrders,
    purchaseOrderLines,
    payments,
    collectionVouchers,
    collectionLines,
    cashTransfers,
    journalEntries,
    journalLines,
    stockMovements,
  ];
}

// The individual readers below are deliberately small and explicit so each
// sheet has a stable shape.

async function prismaSetting(): Promise<BackupSheet> {
  const rows = await prisma.setting.findMany();
  return {
    name: 'Company',
    columns: [
      { header: 'Company', key: 'companyName', width: 28 },
      { header: 'Email', key: 'companyEmail', width: 24 },
      { header: 'Phone', key: 'companyPhone', width: 18 },
      { header: 'Address', key: 'companyAddress', width: 32 },
      { header: 'Tax Card', key: 'taxCardNo', width: 16 },
      { header: 'Register', key: 'commercialRegisterNo', width: 16 },
      { header: 'Base Currency', key: 'baseCurrencyCode', width: 14 },
      { header: 'Tax Enabled', key: 'taxEnabled', width: 12 },
    ],
    rows: rows.map((row) => ({ ...row })),
  };
}

async function prismaCustomer(): Promise<BackupSheet> {
  const rows = await prisma.customer.findMany({
    include: { salesperson: { select: { name: true } } },
    orderBy: { name: 'asc' },
  });
  return {
    name: 'Customers',
    columns: [
      { header: 'Name', key: 'name', width: 28 },
      { header: 'Phone', key: 'phone', width: 18 },
      { header: 'Email', key: 'email', width: 24 },
      { header: 'Address', key: 'address', width: 30 },
      { header: 'Tax Id', key: 'taxId', width: 16 },
      { header: 'Salesperson', key: 'salesperson', width: 20 },
      { header: 'Credit Limit', key: 'creditLimit', width: 14, money: true },
      { header: 'Balance', key: 'balance', width: 14, money: true },
      { header: 'Active', key: 'active', width: 10 },
    ],
    rows: rows.map((row) => ({
      name: row.name,
      phone: row.phone ?? '',
      email: row.email ?? '',
      address: row.address ?? '',
      taxId: row.taxId ?? '',
      salesperson: row.salesperson?.name ?? '',
      creditLimit: n(row.creditLimit),
      balance: n(row.balance),
      active: row.active ? 'Yes' : 'No',
    })),
    totals: { name: 'TOTAL', balance: rows.reduce((sum, row) => sum + n(row.balance), 0) },
  };
}

async function prismaSupplier(): Promise<BackupSheet> {
  const rows = await prisma.supplier.findMany({ orderBy: { name: 'asc' } });
  return {
    name: 'Suppliers',
    columns: [
      { header: 'Name', key: 'name', width: 28 },
      { header: 'Phone', key: 'phone', width: 18 },
      { header: 'Email', key: 'email', width: 24 },
      { header: 'Address', key: 'address', width: 30 },
      { header: 'Tax Id', key: 'taxId', width: 16 },
      { header: 'Balance', key: 'balance', width: 14, money: true },
      { header: 'Active', key: 'active', width: 10 },
    ],
    rows: rows.map((row) => ({
      name: row.name,
      phone: row.phone ?? '',
      email: row.email ?? '',
      address: row.address ?? '',
      taxId: row.taxId ?? '',
      balance: n(row.balance),
      active: row.active ? 'Yes' : 'No',
    })),
    totals: { name: 'TOTAL', balance: rows.reduce((sum, row) => sum + n(row.balance), 0) },
  };
}

async function prismaProduct(): Promise<BackupSheet> {
  const rows = await prisma.product.findMany({
    where: { deletedAt: null },
    include: { category: { select: { name: true } } },
    orderBy: { sku: 'asc' },
  });
  return {
    name: 'Products',
    columns: [
      { header: 'SKU', key: 'sku', width: 16 },
      { header: 'Name', key: 'name', width: 30 },
      { header: 'Category', key: 'category', width: 18 },
      { header: 'Unit', key: 'unit', width: 10 },
      { header: 'Cost Price', key: 'costPrice', width: 14, money: true },
      { header: 'Sale Price', key: 'salePrice', width: 14, money: true },
      { header: 'Reorder Level', key: 'reorderLevel', width: 14 },
      { header: 'Active', key: 'active', width: 10 },
    ],
    rows: rows.map((row) => ({
      sku: row.sku,
      name: row.name,
      category: row.category?.name ?? '',
      unit: row.unit ?? '',
      costPrice: n(row.costPrice),
      salePrice: n(row.salePrice),
      reorderLevel: row.reorderLevel,
      active: row.active ? 'Yes' : 'No',
    })),
  };
}

async function prismaWarehouse(): Promise<BackupSheet> {
  const rows = await prisma.warehouse.findMany({ orderBy: { code: 'asc' } });
  return {
    name: 'Warehouses',
    columns: [
      { header: 'Code', key: 'code', width: 14 },
      { header: 'Name', key: 'name', width: 28 },
      { header: 'Address', key: 'address', width: 30 },
      { header: 'Active', key: 'active', width: 10 },
    ],
    rows: rows.map((row) => ({
      code: row.code,
      name: row.name,
      address: row.address ?? '',
      active: row.active ? 'Yes' : 'No',
    })),
  };
}

async function prismaLocation(): Promise<BackupSheet> {
  const rows = await prisma.location.findMany({
    include: { warehouse: { select: { code: true } } },
    orderBy: [{ warehouseId: 'asc' }, { code: 'asc' }],
  });
  return {
    name: 'Locations',
    columns: [
      { header: 'Warehouse', key: 'warehouse', width: 14 },
      { header: 'Code', key: 'code', width: 14 },
      { header: 'Name', key: 'name', width: 24 },
      { header: 'Active', key: 'active', width: 10 },
    ],
    rows: rows.map((row) => ({
      warehouse: row.warehouse?.code ?? '',
      code: row.code,
      name: row.name ?? '',
      active: row.active ? 'Yes' : 'No',
    })),
  };
}

async function prismaStockLevel(): Promise<BackupSheet> {
  const rows = await prisma.stockLevel.findMany({
    include: {
      product: { select: { sku: true, name: true, costPrice: true } },
      warehouse: { select: { code: true, name: true } },
      location: { select: { code: true } },
    },
    orderBy: [{ warehouseId: 'asc' }, { productId: 'asc' }],
  });
  let totalQty = 0;
  let totalValue = 0;
  const mapped = rows.map((row) => {
    const quantity = row.quantity;
    const cost = n(row.product?.costPrice);
    const value = Math.round(quantity * cost * 100) / 100;
    totalQty += quantity;
    totalValue += value;
    return {
      warehouse: row.warehouse?.code ?? '',
      warehouseName: row.warehouse?.name ?? '',
      location: row.location?.code ?? '',
      sku: row.product?.sku ?? '',
      product: row.product?.name ?? '',
      quantity,
      unitCost: cost,
      value,
    };
  });
  return {
    name: 'Stock Balance',
    columns: [
      { header: 'Warehouse', key: 'warehouse', width: 12 },
      { header: 'Warehouse Name', key: 'warehouseName', width: 20 },
      { header: 'Location', key: 'location', width: 12 },
      { header: 'SKU', key: 'sku', width: 16 },
      { header: 'Product', key: 'product', width: 30 },
      { header: 'Quantity', key: 'quantity', width: 12 },
      { header: 'Unit Cost', key: 'unitCost', width: 14, money: true },
      { header: 'Value', key: 'value', width: 16, money: true },
    ],
    rows: mapped,
    totals: { product: 'TOTAL', quantity: totalQty, value: Math.round(totalValue * 100) / 100 },
  };
}

async function prismaCashBox(): Promise<BackupSheet> {
  const [boxes, payments, transfers] = await Promise.all([
    prisma.cashBox.findMany({ orderBy: { code: 'asc' } }),
    prisma.payment.findMany({
      where: { cancelledAt: null, cashBoxId: { not: null } },
      select: { cashBoxId: true, direction: true, amount: true },
    }),
    prisma.cashTransfer.findMany({
      where: { cancelledAt: null },
      select: { fromBoxId: true, toBoxId: true, amount: true },
    }),
  ]);

  const balanceOf = (boxId: string, opening: number): number => {
    let balance = opening;
    for (const payment of payments) {
      if (payment.cashBoxId !== boxId) continue;
      balance += payment.direction === 'INBOUND' ? n(payment.amount) : -n(payment.amount);
    }
    for (const transfer of transfers) {
      if (transfer.fromBoxId === boxId) balance -= n(transfer.amount);
      if (transfer.toBoxId === boxId) balance += n(transfer.amount);
    }
    return Math.round(balance * 100) / 100;
  };

  const rows = boxes.map((box) => ({
    code: box.code,
    name: box.name,
    type: box.type ?? '',
    active: box.active ? 'Yes' : 'No',
    opening: n(box.openingBalance),
    balance: balanceOf(box.id, n(box.openingBalance)),
  }));

  return {
    name: 'Cash Boxes',
    columns: [
      { header: 'Code', key: 'code', width: 14 },
      { header: 'Name', key: 'name', width: 24 },
      { header: 'Type', key: 'type', width: 12 },
      { header: 'Active', key: 'active', width: 10 },
      { header: 'Opening', key: 'opening', width: 14, money: true },
      { header: 'Balance', key: 'balance', width: 16, money: true },
    ],
    rows,
    totals: {
      name: 'TOTAL',
      balance: Math.round(rows.reduce((sum, row) => sum + row.balance, 0) * 100) / 100,
    },
  };
}

async function prismaSalesOrder(): Promise<BackupSheet> {
  const rows = await prisma.salesOrder.findMany({
    include: {
      customer: { select: { name: true } },
      warehouse: { select: { code: true } },
      user: { select: { name: true } },
    },
    orderBy: { orderDate: 'desc' },
  });
  return {
    name: 'Sales Orders',
    columns: [
      { header: 'Number', key: 'number', width: 16 },
      { header: 'Date', key: 'orderDate', width: 12 },
      { header: 'Customer', key: 'customer', width: 26 },
      { header: 'Warehouse', key: 'warehouse', width: 12 },
      { header: 'Status', key: 'status', width: 18 },
      { header: 'Channel', key: 'channel', width: 12 },
      { header: 'Subtotal', key: 'subtotal', width: 14, money: true },
      { header: 'Discount', key: 'discountTotal', width: 14, money: true },
      { header: 'Tax', key: 'taxTotal', width: 14, money: true },
      { header: 'Total', key: 'total', width: 14, money: true },
      { header: 'Created By', key: 'user', width: 18 },
    ],
    rows: rows.map((row) => ({
      number: row.number,
      orderDate: dateOnly(row.orderDate),
      customer: row.customer?.name ?? '',
      warehouse: row.warehouse?.code ?? '',
      status: row.status,
      channel: row.channel,
      subtotal: n(row.subtotal),
      discountTotal: n(row.discountTotal),
      taxTotal: n(row.taxTotal),
      total: n(row.total),
      user: row.user?.name ?? '',
    })),
    totals: {
      number: 'TOTAL',
      total: rows
        .filter((row) => row.status !== 'CANCELLED')
        .reduce((sum, row) => sum + n(row.total), 0),
    },
  };
}

async function prismaSalesOrderLine(): Promise<BackupSheet> {
  const rows = await prisma.salesOrderLine.findMany({
    include: {
      salesOrder: { select: { number: true, orderDate: true } },
      product: { select: { sku: true, name: true } },
    },
  });
  return {
    name: 'Sales Order Lines',
    columns: [
      { header: 'Order', key: 'order', width: 16 },
      { header: 'Date', key: 'orderDate', width: 12 },
      { header: 'SKU', key: 'sku', width: 16 },
      { header: 'Product', key: 'product', width: 28 },
      { header: 'Quantity', key: 'quantity', width: 12 },
      { header: 'Fulfilled', key: 'fulfilledQty', width: 12 },
      { header: 'Unit Price', key: 'unitPrice', width: 14, money: true },
      { header: 'Discount', key: 'discount', width: 14, money: true },
      { header: 'Tax %', key: 'taxRate', width: 10 },
    ],
    rows: rows.map((row) => ({
      order: row.salesOrder.number,
      orderDate: dateOnly(row.salesOrder.orderDate),
      sku: row.product?.sku ?? '',
      product: row.product?.name ?? '',
      quantity: row.quantity,
      fulfilledQty: row.fulfilledQty,
      unitPrice: n(row.unitPrice),
      discount: n(row.discount),
      taxRate: n(row.taxRate),
    })),
  };
}

async function prismaInvoice(): Promise<BackupSheet> {
  const rows = await prisma.invoice.findMany({
    include: {
      customer: { select: { name: true } },
      salesOrder: { select: { number: true } },
    },
    orderBy: { issueDate: 'desc' },
  });
  return {
    name: 'Invoices',
    columns: [
      { header: 'Number', key: 'number', width: 16 },
      { header: 'Date', key: 'issueDate', width: 12 },
      { header: 'Due Date', key: 'dueDate', width: 12 },
      { header: 'Customer', key: 'customer', width: 26 },
      { header: 'Order', key: 'order', width: 16 },
      { header: 'Status', key: 'status', width: 16 },
      { header: 'Subtotal', key: 'subtotal', width: 14, money: true },
      { header: 'Discount', key: 'discountTotal', width: 14, money: true },
      { header: 'Tax', key: 'taxTotal', width: 14, money: true },
      { header: 'Total', key: 'total', width: 14, money: true },
      { header: 'Paid', key: 'amountPaid', width: 14, money: true },
      { header: 'Balance', key: 'balance', width: 14, money: true },
    ],
    rows: rows.map((row) => ({
      number: row.number,
      issueDate: dateOnly(row.issueDate),
      dueDate: row.dueDate ? dateOnly(row.dueDate) : '',
      customer: row.customer?.name ?? '',
      order: row.salesOrder?.number ?? '',
      status: row.status,
      subtotal: n(row.subtotal),
      discountTotal: n(row.discountTotal),
      taxTotal: n(row.taxTotal),
      total: n(row.total),
      amountPaid: n(row.amountPaid),
      balance: n(row.balance),
    })),
    totals: {
      number: 'TOTAL',
      balance: rows
        .filter((row) => row.status !== 'VOID' && row.status !== 'DRAFT')
        .reduce((sum, row) => sum + n(row.balance), 0),
    },
  };
}

async function prismaInvoiceLine(): Promise<BackupSheet> {
  const rows = await prisma.invoiceLine.findMany({
    include: {
      invoice: { select: { number: true, issueDate: true } },
      product: { select: { sku: true, name: true, costPrice: true } },
    },
  });
  return {
    name: 'Invoice Lines',
    columns: [
      { header: 'Invoice', key: 'invoice', width: 16 },
      { header: 'Date', key: 'issueDate', width: 12 },
      { header: 'SKU', key: 'sku', width: 16 },
      { header: 'Product', key: 'product', width: 28 },
      { header: 'Quantity', key: 'quantity', width: 12 },
      { header: 'Unit Price', key: 'unitPrice', width: 14, money: true },
      { header: 'Discount', key: 'discount', width: 14, money: true },
      { header: 'Tax %', key: 'taxRate', width: 10 },
      { header: 'Cost', key: 'costPrice', width: 14, money: true },
    ],
    rows: rows.map((row) => ({
      invoice: row.invoice.number,
      issueDate: dateOnly(row.invoice.issueDate),
      sku: row.product?.sku ?? '',
      product: row.product?.name ?? '',
      quantity: row.quantity,
      unitPrice: n(row.unitPrice),
      discount: n(row.discount),
      taxRate: n(row.taxRate),
      costPrice: n(row.product?.costPrice),
    })),
  };
}

async function prismaPurchaseOrder(): Promise<BackupSheet> {
  const rows = await prisma.purchaseOrder.findMany({
    include: { supplier: { select: { name: true } }, warehouse: { select: { code: true } } },
    orderBy: { orderDate: 'desc' },
  });
  return {
    name: 'Purchase Orders',
    columns: [
      { header: 'Number', key: 'number', width: 16 },
      { header: 'Date', key: 'orderDate', width: 12 },
      { header: 'Supplier', key: 'supplier', width: 26 },
      { header: 'Warehouse', key: 'warehouse', width: 12 },
      { header: 'Status', key: 'status', width: 18 },
      { header: 'Subtotal', key: 'subtotal', width: 14, money: true },
      { header: 'Tax', key: 'taxTotal', width: 14, money: true },
      { header: 'Total', key: 'total', width: 14, money: true },
    ],
    rows: rows.map((row) => ({
      number: row.number,
      orderDate: dateOnly(row.orderDate),
      supplier: row.supplier?.name ?? '',
      warehouse: row.warehouse?.code ?? '',
      status: row.status,
      subtotal: n(row.subtotal),
      taxTotal: n(row.taxTotal),
      total: n(row.total),
    })),
    totals: {
      number: 'TOTAL',
      total: rows
        .filter((row) => row.status !== 'CANCELLED')
        .reduce((sum, row) => sum + n(row.total), 0),
    },
  };
}

async function prismaPurchaseOrderLine(): Promise<BackupSheet> {
  const rows = await prisma.purchaseOrderLine.findMany({
    include: {
      purchaseOrder: { select: { number: true } },
      product: { select: { sku: true, name: true } },
    },
  });
  return {
    name: 'Purchase Order Lines',
    columns: [
      { header: 'Order', key: 'order', width: 16 },
      { header: 'SKU', key: 'sku', width: 16 },
      { header: 'Product', key: 'product', width: 28 },
      { header: 'Quantity', key: 'quantity', width: 12 },
      { header: 'Received', key: 'receivedQty', width: 12 },
      { header: 'Unit Cost', key: 'unitCost', width: 14, money: true },
      { header: 'Tax %', key: 'taxRate', width: 10 },
    ],
    rows: rows.map((row) => ({
      order: row.purchaseOrder.number,
      sku: row.product?.sku ?? '',
      product: row.product?.name ?? '',
      quantity: row.quantity,
      receivedQty: row.receivedQty,
      unitCost: n(row.unitCost),
      taxRate: n(row.taxRate),
    })),
  };
}

async function prismaPayment(): Promise<BackupSheet> {
  const rows = await prisma.payment.findMany({
    include: {
      customer: { select: { name: true } },
      supplier: { select: { name: true } },
      invoice: { select: { number: true } },
      cashBox: { select: { code: true } },
    },
    orderBy: { paidAt: 'desc' },
  });
  return {
    name: 'Payments',
    columns: [
      { header: 'Number', key: 'number', width: 16 },
      { header: 'Date', key: 'paidAt', width: 12 },
      { header: 'Direction', key: 'direction', width: 12 },
      { header: 'Method', key: 'method', width: 12 },
      { header: 'Customer', key: 'customer', width: 24 },
      { header: 'Supplier', key: 'supplier', width: 24 },
      { header: 'Invoice', key: 'invoice', width: 16 },
      { header: 'Cash Box', key: 'cashBox', width: 14 },
      { header: 'Amount', key: 'amount', width: 16, money: true },
      { header: 'Cancelled', key: 'cancelled', width: 18 },
    ],
    rows: rows.map((row) => ({
      number: row.number,
      paidAt: dateOnly(row.paidAt),
      direction: row.direction,
      method: row.method,
      customer: row.customer?.name ?? '',
      supplier: row.supplier?.name ?? '',
      invoice: row.invoice?.number ?? '',
      cashBox: row.cashBox?.code ?? '',
      amount: n(row.amount),
      cancelled: row.cancelledAt ? stamp(row.cancelledAt) : '',
    })),
  };
}

async function prismaCollectionVoucher(): Promise<BackupSheet> {
  const rows = await prisma.collectionVoucher.findMany({
    include: {
      salesperson: { select: { name: true } },
      cashBox: { select: { code: true } },
      user: { select: { name: true } },
    },
    orderBy: { collectedAt: 'desc' },
  });
  return {
    name: 'Collection Vouchers',
    columns: [
      { header: 'Number', key: 'number', width: 16 },
      { header: 'Date', key: 'collectedAt', width: 12 },
      { header: 'Salesperson', key: 'salesperson', width: 20 },
      { header: 'Cash Box', key: 'cashBox', width: 14 },
      { header: 'Total', key: 'total', width: 16, money: true },
      { header: 'Created By', key: 'user', width: 18 },
      { header: 'Cancelled', key: 'cancelled', width: 18 },
    ],
    rows: rows.map((row) => ({
      number: row.number,
      collectedAt: dateOnly(row.collectedAt),
      salesperson: row.salesperson?.name ?? '',
      cashBox: row.cashBox?.code ?? '',
      total: n(row.total),
      user: row.user?.name ?? '',
      cancelled: row.cancelledAt ? stamp(row.cancelledAt) : '',
    })),
  };
}

async function prismaCollectionLine(): Promise<BackupSheet> {
  const rows = await prisma.collectionLine.findMany({
    include: {
      collection: { select: { number: true, collectedAt: true } },
      customer: { select: { name: true } },
      invoice: { select: { number: true } },
      cashBox: { select: { code: true } },
    },
  });
  return {
    name: 'Collection Lines',
    columns: [
      { header: 'Voucher', key: 'voucher', width: 16 },
      { header: 'Date', key: 'collectedAt', width: 12 },
      { header: 'Customer', key: 'customer', width: 26 },
      { header: 'Invoice', key: 'invoice', width: 16 },
      { header: 'Cash Box', key: 'cashBox', width: 14 },
      { header: 'Amount', key: 'amount', width: 16, money: true },
    ],
    rows: rows.map((row) => ({
      voucher: row.collection.number,
      collectedAt: dateOnly(row.collection.collectedAt),
      customer: row.customer?.name ?? '',
      invoice: row.invoice?.number ?? '',
      cashBox: row.cashBox?.code ?? '',
      amount: n(row.amount),
    })),
  };
}

async function prismaCashTransfer(): Promise<BackupSheet> {
  const rows = await prisma.cashTransfer.findMany({
    include: {
      fromBox: { select: { code: true } },
      toBox: { select: { code: true } },
    },
    orderBy: { transferDate: 'desc' },
  });
  return {
    name: 'Cash Transfers',
    columns: [
      { header: 'Number', key: 'number', width: 16 },
      { header: 'Date', key: 'transferDate', width: 12 },
      { header: 'From', key: 'fromBox', width: 14 },
      { header: 'To', key: 'toBox', width: 14 },
      { header: 'Amount', key: 'amount', width: 16, money: true },
      { header: 'Cancelled', key: 'cancelled', width: 18 },
    ],
    rows: rows.map((row) => ({
      number: row.number,
      transferDate: dateOnly(row.transferDate),
      fromBox: row.fromBox?.code ?? '',
      toBox: row.toBox?.code ?? '',
      amount: n(row.amount),
      cancelled: row.cancelledAt ? stamp(row.cancelledAt) : '',
    })),
  };
}

async function prismaJournalEntry(): Promise<BackupSheet> {
  const rows = await prisma.journalEntry.findMany({
    include: { lines: { select: { debit: true, credit: true } } },
    orderBy: { entryDate: 'desc' },
  });
  return {
    name: 'Journal Entries',
    columns: [
      { header: 'Number', key: 'number', width: 16 },
      { header: 'Date', key: 'entryDate', width: 12 },
      { header: 'Memo', key: 'memo', width: 32 },
      { header: 'Source', key: 'sourceType', width: 18 },
      { header: 'Debit', key: 'debit', width: 14, money: true },
      { header: 'Credit', key: 'credit', width: 14, money: true },
    ],
    rows: rows.map((row) => ({
      number: row.number,
      entryDate: dateOnly(row.entryDate),
      memo: row.memo ?? '',
      sourceType: row.sourceType ?? '',
      debit: Math.round(row.lines.reduce((sum, line) => sum + n(line.debit), 0) * 100) / 100,
      credit: Math.round(row.lines.reduce((sum, line) => sum + n(line.credit), 0) * 100) / 100,
    })),
  };
}

async function prismaJournalLine(): Promise<BackupSheet> {
  const rows = await prisma.journalLine.findMany({
    include: {
      journalEntry: { select: { number: true, entryDate: true } },
      account: { select: { code: true, name: true } },
    },
  });
  return {
    name: 'Journal Lines',
    columns: [
      { header: 'Entry', key: 'entry', width: 16 },
      { header: 'Date', key: 'entryDate', width: 12 },
      { header: 'Account', key: 'account', width: 12 },
      { header: 'Account Name', key: 'accountName', width: 26 },
      { header: 'Description', key: 'description', width: 30 },
      { header: 'Debit', key: 'debit', width: 14, money: true },
      { header: 'Credit', key: 'credit', width: 14, money: true },
    ],
    rows: rows.map((row) => ({
      entry: row.journalEntry.number,
      entryDate: dateOnly(row.journalEntry.entryDate),
      account: row.account?.code ?? '',
      accountName: row.account?.name ?? '',
      description: row.description ?? '',
      debit: n(row.debit),
      credit: n(row.credit),
    })),
  };
}

async function prismaStockMovement(): Promise<BackupSheet> {
  const rows = await prisma.stockMovement.findMany({
    include: {
      product: { select: { sku: true, name: true } },
      location: { select: { code: true } },
      user: { select: { name: true } },
    },
    orderBy: { createdAt: 'desc' },
    take: 20000,
  });
  return {
    name: 'Stock Movements',
    columns: [
      { header: 'Date', key: 'createdAt', width: 18 },
      { header: 'Type', key: 'type', width: 16 },
      { header: 'SKU', key: 'sku', width: 16 },
      { header: 'Product', key: 'product', width: 28 },
      { header: 'Location', key: 'location', width: 12 },
      { header: 'Quantity', key: 'quantity', width: 12 },
      { header: 'Unit Cost', key: 'unitCost', width: 14, money: true },
      { header: 'Reference', key: 'reference', width: 18 },
      { header: 'User', key: 'user', width: 18 },
    ],
    rows: rows.map((row) => ({
      createdAt: stamp(row.createdAt),
      type: row.type,
      sku: row.product?.sku ?? '',
      product: row.product?.name ?? '',
      location: row.location?.code ?? '',
      quantity: row.quantity,
      unitCost: n(row.unitCost),
      reference: row.reference ?? '',
      user: row.user?.name ?? '',
    })),
  };
}
