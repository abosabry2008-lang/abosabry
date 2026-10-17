import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';

export type SalesGroupBy = 'day' | 'month';

export const dayKey = (date: Date): string => date.toISOString().slice(0, 10);

export const monthKey = (date: Date): string => date.toISOString().slice(0, 7);

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
): Promise<SalesReport> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
  const to = toInput ?? now;

  const orders = await prisma.salesOrder.findMany({
    where: { orderDate: { gte: from, lte: to }, status: { not: 'CANCELLED' } },
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
): Promise<TopProductsReport> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const to = toInput ?? now;
  const limit = Number.isFinite(limitInput) ? Math.min(100, Math.max(1, Math.floor(limitInput))) : 10;

  const lines = await prisma.salesOrderLine.findMany({
    where: { salesOrder: { orderDate: { gte: from, lte: to }, status: { not: 'CANCELLED' } } },
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
