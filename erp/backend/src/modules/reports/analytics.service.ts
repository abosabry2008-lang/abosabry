import { Prisma } from '@prisma/client';
import { ApiError } from '../../lib/api-error';
import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';

// ---------------------------------------------------------------------------
// Receivables grouped by salesperson (مديونية العملاء لكل مندوب)
// ---------------------------------------------------------------------------

export interface ReceivablesBySalespersonRow {
  salespersonId: string | null;
  salesperson: string | null;
  customerId: string | null;
  customer: string | null;
  invoices: number;
  total: number;
  paid: number;
  balance: number;
}

export interface ReceivablesBySalespersonReport {
  from: string | null;
  to: string | null;
  rows: ReceivablesBySalespersonRow[];
  totals: { invoices: number; total: number; paid: number; balance: number };
}

/** Outstanding customer balances attributed to the salesperson on the order. */
export async function buildReceivablesBySalesperson(
  fromInput?: Date,
  toInput?: Date,
  userId?: string,
): Promise<ReceivablesBySalespersonReport> {
  const dateWhere: Prisma.InvoiceWhereInput = {};
  if (fromInput || toInput) {
    dateWhere.issueDate = {
      ...(fromInput ? { gte: fromInput } : {}),
      ...(toInput ? { lte: toInput } : {}),
    };
  }

  const invoices = await prisma.invoice.findMany({
    where: {
      status: { in: ['ISSUED', 'PARTIALLY_PAID'] },
      balance: { not: 0 },
      ...dateWhere,
      ...(userId
        ? {
            OR: [
              { customer: { salespersonId: userId } },
              { customer: { salespersonId: null }, salesOrder: { userId } },
            ],
          }
        : {}),
    },
    select: {
      total: true,
      amountPaid: true,
      balance: true,
      customer: {
        select: {
          id: true,
          name: true,
          salesperson: { select: { id: true, name: true } },
        },
      },
      salesOrder: {
        select: { userId: true, user: { select: { id: true, name: true } } },
      },
    },
  });

  const map = new Map<string, ReceivablesBySalespersonRow>();
  for (const invoice of invoices) {
    // The customer's assigned representative wins; otherwise the order's creator.
    const rep = invoice.customer?.salesperson ?? invoice.salesOrder?.user ?? null;
    const customer = invoice.customer;
    const key = `${rep?.id ?? '-'}::${customer?.id ?? '-'}`;
    const row =
      map.get(key) ??
      ({
        salespersonId: rep?.id ?? null,
        salesperson: rep?.name ?? null,
        customerId: customer?.id ?? null,
        customer: customer?.name ?? null,
        invoices: 0,
        total: 0,
        paid: 0,
        balance: 0,
      } satisfies ReceivablesBySalespersonRow);
    row.invoices += 1;
    row.total = round2(row.total + Number(invoice.total));
    row.paid = round2(row.paid + Number(invoice.amountPaid));
    row.balance = round2(row.balance + Number(invoice.balance));
    map.set(key, row);
  }

  const rows = [...map.values()].sort(
    (a, b) => (a.salesperson ?? '').localeCompare(b.salesperson ?? '') || b.balance - a.balance,
  );

  const totals = rows.reduce(
    (acc, row) => ({
      invoices: acc.invoices + row.invoices,
      total: round2(acc.total + row.total),
      paid: round2(acc.paid + row.paid),
      balance: round2(acc.balance + row.balance),
    }),
    { invoices: 0, total: 0, paid: 0, balance: 0 },
  );

  return {
    from: fromInput ? fromInput.toISOString() : null,
    to: toInput ? toInput.toISOString() : null,
    rows,
    totals,
  };
}

// ---------------------------------------------------------------------------
// Supplier payables in full (مديونية الموردين بالكامل)
// ---------------------------------------------------------------------------

export interface SupplierPayablesRow {
  supplierId: string;
  supplier: string;
  phone: string | null;
  purchaseOrders: number;
  purchases: number;
  paid: number;
  balance: number;
}

export interface SupplierPayablesReport {
  from: string | null;
  to: string | null;
  rows: SupplierPayablesRow[];
  totals: { purchaseOrders: number; purchases: number; paid: number; balance: number };
}

/** Every supplier with a non-zero balance or purchases in the period. */
export async function buildSupplierPayables(
  fromInput?: Date,
  toInput?: Date,
): Promise<SupplierPayablesReport> {
  const dateRange =
    fromInput || toInput
      ? {
          ...(fromInput ? { gte: fromInput } : {}),
          ...(toInput ? { lte: toInput } : {}),
        }
      : undefined;

  const [suppliers, purchaseGroups, paymentGroups] = await Promise.all([
    prisma.supplier.findMany({
      select: { id: true, name: true, phone: true, balance: true },
    }),
    prisma.purchaseOrder.groupBy({
      by: ['supplierId'],
      where: { status: { not: 'CANCELLED' }, ...(dateRange ? { orderDate: dateRange } : {}) },
      _sum: { total: true },
      _count: { _all: true },
    }),
    prisma.payment.groupBy({
      by: ['supplierId'],
      where: {
        direction: 'OUTBOUND',
        supplierId: { not: null },
        ...(dateRange ? { paidAt: dateRange } : {}),
      },
      _sum: { amount: true },
    }),
  ]);

  const purchasesById = new Map(
    purchaseGroups.map((group) => [
      group.supplierId,
      { total: round2(Number(group._sum.total ?? 0)), count: group._count._all },
    ]),
  );
  const paidById = new Map(
    paymentGroups.map((group) => [group.supplierId ?? '', round2(Number(group._sum.amount ?? 0))]),
  );

  const rows: SupplierPayablesRow[] = [];
  for (const supplier of suppliers) {
    const purchases = purchasesById.get(supplier.id) ?? { total: 0, count: 0 };
    const paid = paidById.get(supplier.id) ?? 0;
    const balance = round2(Number(supplier.balance));
    if (balance === 0 && purchases.total === 0) continue;
    rows.push({
      supplierId: supplier.id,
      supplier: supplier.name,
      phone: supplier.phone,
      purchaseOrders: purchases.count,
      purchases: purchases.total,
      paid,
      balance,
    });
  }

  rows.sort((a, b) => b.balance - a.balance || a.supplier.localeCompare(b.supplier));

  const totals = rows.reduce(
    (acc, row) => ({
      purchaseOrders: acc.purchaseOrders + row.purchaseOrders,
      purchases: round2(acc.purchases + row.purchases),
      paid: round2(acc.paid + row.paid),
      balance: round2(acc.balance + row.balance),
    }),
    { purchaseOrders: 0, purchases: 0, paid: 0, balance: 0 },
  );

  return {
    from: fromInput ? fromInput.toISOString() : null,
    to: toInput ? toInput.toISOString() : null,
    rows,
    totals,
  };
}

// ---------------------------------------------------------------------------
// Stock balance with quantity and value (رصيد المخزون للجرد والمراجعة)
// ---------------------------------------------------------------------------

export interface StockBalanceRow {
  productId: string;
  sku: string;
  name: string;
  unit: string;
  category: string | null;
  warehouseId: string;
  warehouse: string;
  quantity: number;
  reserved: number;
  available: number;
  unitCost: number;
  costValue: number;
  salePrice: number;
  retailValue: number;
}

export interface StockBalanceReport {
  rows: StockBalanceRow[];
  totals: { quantity: number; reserved: number; available: number; costValue: number; retailValue: number };
}

/** On-hand quantity and value per product/warehouse, for counting and review. */
export async function buildStockBalance(
  warehouseId?: string,
  categoryId?: string,
): Promise<StockBalanceReport> {
  const levels = await prisma.stockLevel.findMany({
    where: {
      ...(warehouseId ? { warehouseId } : {}),
      ...(categoryId ? { product: { categoryId } } : {}),
    },
    include: {
      product: {
        select: {
          id: true,
          sku: true,
          name: true,
          unit: true,
          costPrice: true,
          salePrice: true,
          category: { select: { name: true } },
        },
      },
      warehouse: { select: { id: true, name: true } },
    },
  });

  const map = new Map<string, StockBalanceRow>();
  for (const level of levels) {
    const key = `${level.productId}::${level.warehouseId}`;
    const row =
      map.get(key) ??
      ({
        productId: level.productId,
        sku: level.product.sku,
        name: level.product.name,
        unit: level.product.unit,
        category: level.product.category?.name ?? null,
        warehouseId: level.warehouseId,
        warehouse: level.warehouse.name,
        quantity: 0,
        reserved: 0,
        available: 0,
        unitCost: Number(level.product.costPrice),
        costValue: 0,
        salePrice: Number(level.product.salePrice),
        retailValue: 0,
      } satisfies StockBalanceRow);
    row.quantity += level.quantity;
    row.reserved += level.reserved;
    map.set(key, row);
  }

  const rows = [...map.values()].filter((row) => row.quantity !== 0 || row.reserved !== 0);
  for (const row of rows) {
    row.available = row.quantity - row.reserved;
    row.costValue = round2(row.quantity * row.unitCost);
    row.retailValue = round2(row.quantity * row.salePrice);
  }
  rows.sort(
    (a, b) => a.name.localeCompare(b.name) || a.warehouse.localeCompare(b.warehouse),
  );

  const totals = rows.reduce(
    (acc, row) => ({
      quantity: acc.quantity + row.quantity,
      reserved: acc.reserved + row.reserved,
      available: acc.available + row.available,
      costValue: round2(acc.costValue + row.costValue),
      retailValue: round2(acc.retailValue + row.retailValue),
    }),
    { quantity: 0, reserved: 0, available: 0, costValue: 0, retailValue: 0 },
  );

  return { rows, totals };
}

// ---------------------------------------------------------------------------
// Item movement / stock card (تتبع حركة صنف)
// ---------------------------------------------------------------------------

export interface ItemMovementRow {
  date: string;
  type: string;
  reference: string | null;
  warehouse: string | null;
  location: string | null;
  quantity: number;
  dir: 'IN' | 'OUT';
  in: number;
  out: number;
  balance: number;
  unitCost: number;
  value: number;
}

export interface ItemMovementReport {
  product: { id: string; sku: string; name: string; unit: string; unitCost: number };
  warehouseId: string | null;
  from: string | null;
  to: string | null;
  opening: { quantity: number; value: number };
  rows: ItemMovementRow[];
  totals: {
    in: { quantity: number; value: number };
    out: { quantity: number; value: number };
    closing: { quantity: number; value: number };
    inQty: number;
    outQty: number;
    inValue: number;
    outValue: number;
    closingQty: number;
    closingValue: number;
  };
}

/** Every movement of one product with a running quantity balance. */
export async function buildItemMovement(
  productId: string,
  fromInput?: Date,
  toInput?: Date,
  warehouseId?: string,
): Promise<ItemMovementReport> {
  const product = await prisma.product.findUnique({
    where: { id: productId },
    select: { id: true, sku: true, name: true, unit: true, costPrice: true },
  });
  if (!product) throw ApiError.notFound('Product not found');

  const base: Prisma.StockMovementWhereInput = {
    productId,
    ...(warehouseId ? { warehouseId } : {}),
  };

  const [openingRows, movements, warehouses] = await Promise.all([
    fromInput
      ? prisma.stockMovement.findMany({
          where: { ...base, createdAt: { lt: fromInput } },
          select: { quantity: true, unitCost: true },
        })
      : Promise.resolve([] as { quantity: number; unitCost: Prisma.Decimal }[]),
    prisma.stockMovement.findMany({
      where: {
        ...base,
        ...(fromInput || toInput
          ? {
              createdAt: {
                ...(fromInput ? { gte: fromInput } : {}),
                ...(toInput ? { lte: toInput } : {}),
              },
            }
          : {}),
      },
      orderBy: { createdAt: 'asc' },
      take: 2000,
      include: { location: { select: { code: true, name: true } } },
    }),
    prisma.warehouse.findMany({ select: { id: true, name: true } }),
  ]);

  const warehouseById = new Map(warehouses.map((warehouse) => [warehouse.id, warehouse.name]));

  let openingQty = 0;
  let openingValue = 0;
  for (const movement of openingRows) {
    openingQty += movement.quantity;
    openingValue += movement.quantity * Number(movement.unitCost);
  }
  openingValue = round2(openingValue);

  let running = openingQty;
  let inQty = 0;
  let outQty = 0;
  let inValue = 0;
  let outValue = 0;

  const rows: ItemMovementRow[] = movements.map((movement) => {
    const value = round2(movement.quantity * Number(movement.unitCost));
    running += movement.quantity;
    if (movement.quantity >= 0) {
      inQty += movement.quantity;
      inValue = round2(inValue + value);
    } else {
      outQty += -movement.quantity;
      outValue = round2(outValue - value);
    }
    return {
      date: movement.createdAt.toISOString(),
      type: movement.type,
      reference: movement.reference,
      warehouse: warehouseById.get(movement.warehouseId) ?? null,
      location: movement.location.name ?? movement.location.code,
      quantity: movement.quantity,
      dir: movement.quantity >= 0 ? 'IN' : 'OUT',
      in: movement.quantity > 0 ? movement.quantity : 0,
      out: movement.quantity < 0 ? -movement.quantity : 0,
      balance: running,
      unitCost: Number(movement.unitCost),
      value,
    };
  });

  const closingValue = round2(openingValue + inValue - outValue);

  return {
    product: {
      id: product.id,
      sku: product.sku,
      name: product.name,
      unit: product.unit,
      unitCost: Number(product.costPrice),
    },
    warehouseId: warehouseId ?? null,
    from: fromInput ? fromInput.toISOString() : null,
    to: toInput ? toInput.toISOString() : null,
    opening: { quantity: openingQty, value: openingValue },
    rows,
    totals: {
      in: { quantity: inQty, value: inValue },
      out: { quantity: outQty, value: outValue },
      closing: { quantity: running, value: closingValue },
      inQty,
      outQty,
      inValue,
      outValue,
      closingQty: running,
      closingValue,
    },
  };
}
