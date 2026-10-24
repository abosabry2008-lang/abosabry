import { round2 } from '../../lib/money';
import { localDayKey, localMonthKey } from '../../lib/local-time';
import { prisma } from '../../lib/prisma';
import { salesOrderAccessWhere, type ScopeUser } from '../../lib/salesperson-scope';

export type SalesGroupBy = 'day' | 'month';

export const dayKey = (date: Date): string => localDayKey(date);

export const monthKey = (date: Date): string => localMonthKey(date);

export interface SalesReportBucket {
  period: string;
  orders: number;
  subtotal: number;
  tax: number;
  discount: number;
  total: number;
}

export interface SalesReport {
  from: string;
  to: string;
  groupBy: SalesGroupBy;
  totals: {
    orders: number;
    subtotal: number;
    tax: number;
    discount: number;
    total: number;
  };
  series: SalesReportBucket[];
}

/** Sales totals grouped by day or month. Defaults to the current year. */
export async function buildSalesReport(
  fromInput?: Date,
  toInput?: Date,
  groupBy: SalesGroupBy = 'day',
  user?: ScopeUser,
): Promise<SalesReport> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
  const to = toInput ?? now;
  const access = user ? salesOrderAccessWhere(user) : null;

  const orders = await prisma.salesOrder.findMany({
    where: { orderDate: { gte: from, lte: to }, status: { not: 'CANCELLED' }, ...(access ?? {}) },
    select: { orderDate: true, subtotal: true, taxTotal: true, discountTotal: true, total: true },
  });

  const buckets = new Map<string, SalesReportBucket>();
  let subtotal = 0;
  let tax = 0;
  let discount = 0;
  let total = 0;

  for (const order of orders) {
    const key = groupBy === 'month' ? monthKey(order.orderDate) : dayKey(order.orderDate);
    const bucket =
      buckets.get(key) ??
      { period: key, orders: 0, subtotal: 0, tax: 0, discount: 0, total: 0 };
    bucket.orders += 1;
    bucket.subtotal = round2(bucket.subtotal + Number(order.subtotal));
    bucket.tax = round2(bucket.tax + Number(order.taxTotal));
    bucket.discount = round2(bucket.discount + Number(order.discountTotal));
    bucket.total = round2(bucket.total + Number(order.total));
    buckets.set(key, bucket);

    subtotal += Number(order.subtotal);
    tax += Number(order.taxTotal);
    discount += Number(order.discountTotal);
    total += Number(order.total);
  }

  return {
    from: dayKey(from),
    to: dayKey(to),
    groupBy,
    totals: {
      orders: orders.length,
      subtotal: round2(subtotal),
      tax: round2(tax),
      discount: round2(discount),
      total: round2(total),
    },
    series: [...buckets.values()].sort((a, b) => a.period.localeCompare(b.period)),
  };
}

export interface InventoryValuationRow {
  productId: string;
  sku: string;
  name: string;
  unit: string;
  warehouse: { id: string; code: string; name: string };
  location: { id: string; code: string; name: string | null };
  quantity: number;
  unitCost: number;
  unitPrice: number;
  costValue: number;
  retailValue: number;
}

export interface InventoryValuationReport {
  rows: InventoryValuationRow[];
  totals: {
    lines: number;
    units: number;
    costValue: number;
    retailValue: number;
  };
}

/** Stock-on-hand valuation, optionally limited to a single warehouse. */
export async function buildInventoryValuation(warehouseId?: string): Promise<InventoryValuationReport> {
  const levels = await prisma.stockLevel.findMany({
    where: warehouseId ? { warehouseId } : {},
    orderBy: [{ warehouseId: 'asc' }, { productId: 'asc' }],
    include: {
      product: { select: { id: true, sku: true, name: true, unit: true, costPrice: true, salePrice: true } },
      warehouse: { select: { id: true, code: true, name: true } },
      location: { select: { id: true, code: true, name: true } },
    },
  });

  const rows: InventoryValuationRow[] = levels
    .filter((level) => level.quantity !== 0)
    .map((level) => {
      const cost = Number(level.product.costPrice);
      const sale = Number(level.product.salePrice);
      return {
        productId: level.product.id,
        sku: level.product.sku,
        name: level.product.name,
        unit: level.product.unit,
        warehouse: level.warehouse,
        location: level.location,
        quantity: level.quantity,
        unitCost: cost,
        unitPrice: sale,
        costValue: round2(level.quantity * cost),
        retailValue: round2(level.quantity * sale),
      };
    });

  return {
    rows,
    totals: {
      lines: rows.length,
      units: rows.reduce((sum, row) => sum + row.quantity, 0),
      costValue: round2(rows.reduce((sum, row) => sum + row.costValue, 0)),
      retailValue: round2(rows.reduce((sum, row) => sum + row.retailValue, 0)),
    },
  };
}

export interface TopProductRow {
  productId: string;
  sku: string;
  name: string;
  quantitySold: number;
  revenue: number;
  orders: number;
}

export interface TopProductsReport {
  from: string;
  to: string;
  rows: TopProductRow[];
}

/** Best-selling products by revenue over a date range. Defaults to the last 30 days. */
export async function buildTopProducts(
  fromInput?: Date,
  toInput?: Date,
  limitInput = 10,
  user?: ScopeUser,
): Promise<TopProductsReport> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const to = toInput ?? now;
  const limit = Number.isFinite(limitInput) ? Math.min(100, Math.max(1, Math.floor(limitInput))) : 10;
  const access = user ? salesOrderAccessWhere(user) : null;

  const lines = await prisma.salesOrderLine.findMany({
    where: {
      salesOrder: {
        orderDate: { gte: from, lte: to },
        status: { not: 'CANCELLED' },
        ...(access ?? {}),
      },
    },
    select: { productId: true, quantity: true, unitPrice: true, salesOrderId: true },
  });

  const byProduct = new Map<string, { quantity: number; revenue: number; orders: Set<string> }>();
  for (const line of lines) {
    const entry = byProduct.get(line.productId) ?? { quantity: 0, revenue: 0, orders: new Set<string>() };
    entry.quantity += line.quantity;
    entry.revenue += line.quantity * Number(line.unitPrice);
    entry.orders.add(line.salesOrderId);
    byProduct.set(line.productId, entry);
  }

  const ranked = [...byProduct.entries()].sort((a, b) => b[1].revenue - a[1].revenue).slice(0, limit);

  const products = ranked.length
    ? await prisma.product.findMany({
        where: { id: { in: ranked.map(([id]) => id) } },
        select: { id: true, sku: true, name: true },
      })
    : [];
  const byId = new Map(products.map((product) => [product.id, product]));

  return {
    from: dayKey(from),
    to: dayKey(to),
    rows: ranked.map(([productId, stats]) => ({
      productId,
      sku: byId.get(productId)?.sku ?? '',
      name: byId.get(productId)?.name ?? '',
      quantitySold: stats.quantity,
      revenue: round2(stats.revenue),
      orders: stats.orders.size,
    })),
  };
}

// ---------------------------------------------------------------------------
// Purchases (تقرير المشتريات حسب الفترة)
// ---------------------------------------------------------------------------

export interface PurchasesReportBucket {
  period: string;
  orders: number;
  subtotal: number;
  tax: number;
  total: number;
}

export interface PurchasesReport {
  from: string;
  to: string;
  groupBy: SalesGroupBy;
  totals: { orders: number; subtotal: number; tax: number; total: number };
  series: PurchasesReportBucket[];
}

/** Purchase order totals grouped by day or month. Defaults to the current year. */
export async function buildPurchasesReport(
  fromInput?: Date,
  toInput?: Date,
  groupBy: SalesGroupBy = 'day',
): Promise<PurchasesReport> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
  const to = toInput ?? now;

  const orders = await prisma.purchaseOrder.findMany({
    where: { orderDate: { gte: from, lte: to }, status: { not: 'CANCELLED' } },
    select: { orderDate: true, subtotal: true, taxTotal: true, total: true },
  });

  const buckets = new Map<string, PurchasesReportBucket>();
  let subtotal = 0;
  let tax = 0;
  let total = 0;

  for (const order of orders) {
    const key = groupBy === 'month' ? monthKey(order.orderDate) : dayKey(order.orderDate);
    const bucket = buckets.get(key) ?? { period: key, orders: 0, subtotal: 0, tax: 0, total: 0 };
    bucket.orders += 1;
    bucket.subtotal = round2(bucket.subtotal + Number(order.subtotal));
    bucket.tax = round2(bucket.tax + Number(order.taxTotal));
    bucket.total = round2(bucket.total + Number(order.total));
    buckets.set(key, bucket);

    subtotal += Number(order.subtotal);
    tax += Number(order.taxTotal);
    total += Number(order.total);
  }

  return {
    from: dayKey(from),
    to: dayKey(to),
    groupBy,
    totals: {
      orders: orders.length,
      subtotal: round2(subtotal),
      tax: round2(tax),
      total: round2(total),
    },
    series: [...buckets.values()].sort((a, b) => a.period.localeCompare(b.period)),
  };
}

// ---------------------------------------------------------------------------
// Sales profit (أرباح المبيعات)
// ---------------------------------------------------------------------------

export interface ProfitRow {
  productId: string;
  sku: string;
  name: string;
  quantity: number;
  revenue: number;
  cost: number;
  profit: number;
}

export interface ProfitReport {
  from: string;
  to: string;
  totals: {
    invoices: number;
    returns: number;
    grossRevenue: number;
    returnsValue: number;
    revenue: number;
    cost: number;
    returnCost: number;
    profit: number;
    margin: number;
  };
  rows: ProfitRow[];
}

/** Revenue (net of tax) minus product cost for issued invoices in a period. */
export async function buildProfitReport(
  fromInput?: Date,
  toInput?: Date,
): Promise<ProfitReport> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
  const to = toInput ?? now;

  const invoices = await prisma.invoice.findMany({
    where: { status: { notIn: ['DRAFT', 'VOID'] }, issueDate: { gte: from, lte: to } },
    select: {
      id: true,
      lines: {
        select: {
          productId: true,
          quantity: true,
          unitPrice: true,
          unitCost: true,
          discount: true,
          product: { select: { sku: true, name: true, costPrice: true } },
        },
      },
    },
  });

  const returnOrders = await prisma.returnOrder.findMany({
    where: {
      type: 'CUSTOMER_RETURN',
      status: 'POSTED',
      returnDate: { gte: from, lte: to },
    },
    select: {
      lines: {
        select: {
          productId: true,
          quantity: true,
          unitPrice: true,
          unitCost: true,
          product: { select: { sku: true, name: true, costPrice: true } },
        },
      },
    },
  });

  const byProduct = new Map<string, ProfitRow & { name: string }>();
  let grossRevenue = 0;
  let invoiceCost = 0;
  let returnsValue = 0;
  let returnCost = 0;

  const rowFor = (line: {
    productId: string;
    product: { sku: string; name: string };
  }) =>
    byProduct.get(line.productId) ?? {
      productId: line.productId,
      sku: line.product.sku,
      name: line.product.name,
      quantity: 0,
      revenue: 0,
      cost: 0,
      profit: 0,
    };

  for (const invoice of invoices) {
    for (const line of invoice.lines) {
      const net = Math.max(0, round2(line.quantity * Number(line.unitPrice) - Number(line.discount)));
      const unitCost =
        Number(line.unitCost) || (line.product ? Number(line.product.costPrice) : 0);
      const lineCost = round2(line.quantity * unitCost);
      grossRevenue += net;
      invoiceCost += lineCost;

      if (!line.productId || !line.product) continue;
      const row = rowFor({ productId: line.productId, product: line.product });
      row.quantity += line.quantity;
      row.revenue = round2(row.revenue + net);
      row.cost = round2(row.cost + lineCost);
      byProduct.set(line.productId, row);
    }
  }

  // Posted customer returns reverse both revenue and cost.
  for (const order of returnOrders) {
    for (const line of order.lines) {
      const value = round2(line.quantity * Number(line.unitPrice));
      const unitCost =
        Number(line.unitCost) ||
        (line.product ? Number(line.product.costPrice) : 0);
      const valueCost = round2(line.quantity * unitCost);
      returnsValue += value;
      returnCost += valueCost;

      if (!line.product) continue;
      const row = rowFor({ productId: line.productId, product: line.product });
      row.quantity -= line.quantity;
      row.revenue = round2(row.revenue - value);
      row.cost = round2(row.cost - valueCost);
      byProduct.set(line.productId, row);
    }
  }

  const revenue = round2(grossRevenue - returnsValue);
  const cost = round2(invoiceCost - returnCost);

  const rows = [...byProduct.values()]
    .map((row) => ({ ...row, profit: round2(row.revenue - row.cost) }))
    .sort((a, b) => b.profit - a.profit);

  const profit = round2(revenue - cost);
  return {
    from: dayKey(from),
    to: dayKey(to),
    totals: {
      invoices: invoices.length,
      returns: returnOrders.length,
      grossRevenue: round2(grossRevenue),
      returnsValue: round2(returnsValue),
      revenue: round2(revenue),
      cost: round2(cost),
      returnCost: round2(returnCost),
      profit,
      margin: revenue > 0 ? round2((profit / revenue) * 100) : 0,
    },
    rows,
  };
}

// ---------------------------------------------------------------------------
// Tax summary (تقرير ضريبة القيمة المضافة)
// ---------------------------------------------------------------------------

export interface TaxReportBucket {
  period: string;
  salesTax: number;
  purchaseTax: number;
  netTax: number;
}

export interface TaxReport {
  from: string;
  to: string;
  totals: {
    salesTax: number;
    purchaseTax: number;
    netTax: number;
    taxableSales: number;
    taxablePurchases: number;
  };
  series: TaxReportBucket[];
}

/** Output tax charged on invoices minus input tax on purchase orders. */
export async function buildTaxReport(fromInput?: Date, toInput?: Date): Promise<TaxReport> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
  const to = toInput ?? now;

  const [invoices, purchaseOrders] = await Promise.all([
    prisma.invoice.findMany({
      where: { status: { notIn: ['DRAFT', 'VOID'] }, issueDate: { gte: from, lte: to } },
      select: { issueDate: true, taxTotal: true, total: true },
    }),
    prisma.purchaseOrder.findMany({
      where: { status: { not: 'CANCELLED' }, orderDate: { gte: from, lte: to } },
      select: { orderDate: true, taxTotal: true, total: true },
    }),
  ]);

  const buckets = new Map<string, TaxReportBucket>();
  let salesTax = 0;
  let purchaseTax = 0;
  let taxableSales = 0;
  let taxablePurchases = 0;

  const bucketFor = (key: string): TaxReportBucket => {
    const existing = buckets.get(key);
    if (existing) return existing;
    const created: TaxReportBucket = { period: key, salesTax: 0, purchaseTax: 0, netTax: 0 };
    buckets.set(key, created);
    return created;
  };

  for (const invoice of invoices) {
    const amount = Number(invoice.taxTotal);
    salesTax += amount;
    taxableSales += Number(invoice.total);
    const bucket = bucketFor(monthKey(invoice.issueDate));
    bucket.salesTax = round2(bucket.salesTax + amount);
  }
  for (const order of purchaseOrders) {
    const amount = Number(order.taxTotal);
    purchaseTax += amount;
    taxablePurchases += Number(order.total);
    const bucket = bucketFor(monthKey(order.orderDate));
    bucket.purchaseTax = round2(bucket.purchaseTax + amount);
  }

  const series = [...buckets.values()]
    .map((bucket) => ({ ...bucket, netTax: round2(bucket.salesTax - bucket.purchaseTax) }))
    .sort((a, b) => a.period.localeCompare(b.period));

  return {
    from: dayKey(from),
    to: dayKey(to),
    totals: {
      salesTax: round2(salesTax),
      purchaseTax: round2(purchaseTax),
      netTax: round2(salesTax - purchaseTax),
      taxableSales: round2(taxableSales),
      taxablePurchases: round2(taxablePurchases),
    },
    series,
  };
}
