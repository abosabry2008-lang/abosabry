import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { invoiceAccessWhere, isSalesperson, type ScopeUser } from '../../lib/salesperson-scope';

/**
 * Additional operational reports that complement `reports.service.ts` and
 * `analytics.service.ts`. Every builder returns a plain JSON-friendly object
 * shaped as `{ from, to, totals, rows }` so the mobile/web client can render it
 * with one generic table screen.
 */

function startOfYear(): Date {
  const now = new Date();
  return new Date(now.getFullYear(), 0, 1);
}

export function resolveRange(fromInput?: Date, toInput?: Date): {
  from: Date;
  to: Date;
} {
  return {
    from: fromInput ?? startOfYear(),
    to: toInput ?? new Date(),
  };
}

type Numeric = { toString(): string } | number | null | undefined;

const num = (value: Numeric): number => round2(Number(value ?? 0));

// ---------------------------------------------------------------------------
// Sales by customer
// ---------------------------------------------------------------------------

export interface SalesByCustomerRow {
  customerId: string | null;
  customerName: string;
  code: string;
  invoices: number;
  total: number;
  paid: number;
  balance: number;
  cost: number;
  profit: number;
}

export async function buildSalesByCustomer(fromInput?: Date, toInput?: Date, user?: ScopeUser) {
  const { from, to } = resolveRange(fromInput, toInput);
  const invoices = await prisma.invoice.findMany({
    where: {
      issueDate: { gte: from, lte: to },
      status: { in: ['ISSUED', 'PARTIALLY_PAID', 'PAID'] },
      ...(user ? (invoiceAccessWhere(user) ?? {}) : {}),
    },
    select: {
      customerId: true,
      total: true,
      amountPaid: true,
      balance: true,
      customer: { select: { name: true, code: true } },
      lines: {
        select: {
          quantity: true,
          unitPrice: true,
          discount: true,
          product: { select: { costPrice: true } },
        },
      },
    },
  });

  const map = new Map<string, SalesByCustomerRow>();
  for (const invoice of invoices) {
    const key = invoice.customerId ?? '__walk_in__';
    const row =
      map.get(key) ??
      ({
        customerId: invoice.customerId,
        customerName: invoice.customer?.name ?? '',
        code: invoice.customer?.code ?? '',
        invoices: 0,
        total: 0,
        paid: 0,
        balance: 0,
        cost: 0,
        profit: 0,
      } satisfies SalesByCustomerRow);
    const cost = round2(
      invoice.lines.reduce(
        (sum, line) =>
          sum +
          line.quantity * num(line.product?.costPrice),
        0,
      ),
    );
    const revenue = round2(
      invoice.lines.reduce(
        (sum, line) =>
          sum +
          Math.max(
            0,
            line.quantity * num(line.unitPrice) - num(line.discount),
          ),
        0,
      ),
    );
    row.invoices += 1;
    row.total = round2(row.total + num(invoice.total));
    row.paid = round2(row.paid + num(invoice.amountPaid));
    row.balance = round2(row.balance + num(invoice.balance));
    row.cost = round2(row.cost + cost);
    row.profit = round2(row.profit + revenue - cost);
    map.set(key, row);
  }

  const rows = [...map.values()].sort((a, b) => b.total - a.total);
  return {
    from,
    to,
    totals: {
      customers: rows.length,
      invoices: rows.reduce((sum, row) => sum + row.invoices, 0),
      total: round2(rows.reduce((sum, row) => sum + row.total, 0)),
      paid: round2(rows.reduce((sum, row) => sum + row.paid, 0)),
      balance: round2(rows.reduce((sum, row) => sum + row.balance, 0)),
      cost: round2(rows.reduce((sum, row) => sum + row.cost, 0)),
      profit: round2(rows.reduce((sum, row) => sum + row.profit, 0)),
    },
    rows,
  };
}

// ---------------------------------------------------------------------------
// Sales by category
// ---------------------------------------------------------------------------

export async function buildSalesByCategory(fromInput?: Date, toInput?: Date, user?: ScopeUser) {
  const { from, to } = resolveRange(fromInput, toInput);
  const lines = await prisma.invoiceLine.findMany({
    where: {
      invoice: {
        issueDate: { gte: from, lte: to },
        status: { in: ['ISSUED', 'PARTIALLY_PAID', 'PAID'] },
        ...(user ? (invoiceAccessWhere(user) ?? {}) : {}),
      },
    },
    select: {
      quantity: true,
      total: true,
      product: {
        select: {
          costPrice: true,
          categoryId: true,
          category: { select: { name: true } },
        },
      },
    },
  });

  const map = new Map<
    string,
    {
      categoryId: string | null;
      categoryName: string;
      quantity: number;
      revenue: number;
      cost: number;
      profit: number;
    }
  >();
  for (const line of lines) {
    const categoryId = line.product?.categoryId ?? null;
    const key = categoryId ?? '__uncategorized__';
    const row =
      map.get(key) ??
      {
        categoryId,
        categoryName: line.product?.category?.name ?? '',
        quantity: 0,
        revenue: 0,
        cost: 0,
        profit: 0,
      };
    const revenue = num(line.total);
    const cost = round2(line.quantity * num(line.product?.costPrice));
    row.quantity += line.quantity;
    row.revenue = round2(row.revenue + revenue);
    row.cost = round2(row.cost + cost);
    row.profit = round2(row.profit + revenue - cost);
    map.set(key, row);
  }

  const rows = [...map.values()].sort((a, b) => b.revenue - a.revenue);
  return {
    from,
    to,
    totals: {
      categories: rows.length,
      quantity: rows.reduce((sum, row) => sum + row.quantity, 0),
      revenue: round2(rows.reduce((sum, row) => sum + row.revenue, 0)),
      cost: round2(rows.reduce((sum, row) => sum + row.cost, 0)),
      profit: round2(rows.reduce((sum, row) => sum + row.profit, 0)),
    },
    rows,
  };
}

// ---------------------------------------------------------------------------
// Sales by salesperson
// ---------------------------------------------------------------------------

export async function buildSalesBySalesperson(fromInput?: Date, toInput?: Date, user?: ScopeUser) {
  const { from, to } = resolveRange(fromInput, toInput);
  const invoices = await prisma.invoice.findMany({
    where: {
      issueDate: { gte: from, lte: to },
      status: { in: ['ISSUED', 'PARTIALLY_PAID', 'PAID'] },
      ...(user ? (invoiceAccessWhere(user) ?? {}) : {}),
    },
    select: {
      total: true,
      amountPaid: true,
      balance: true,
      customer: {
        select: {
          salespersonId: true,
          salesperson: { select: { name: true } },
        },
      },
    },
  });

  const map = new Map<
    string,
    {
      salespersonId: string | null;
      salespersonName: string;
      invoices: number;
      total: number;
      paid: number;
      balance: number;
    }
  >();
  for (const invoice of invoices) {
    const salespersonId = invoice.customer?.salespersonId ?? null;
    const key = salespersonId ?? '__unassigned__';
    const row =
      map.get(key) ??
      {
        salespersonId,
        salespersonName: invoice.customer?.salesperson?.name ?? '',
        invoices: 0,
        total: 0,
        paid: 0,
        balance: 0,
      };
    row.invoices += 1;
    row.total = round2(row.total + num(invoice.total));
    row.paid = round2(row.paid + num(invoice.amountPaid));
    row.balance = round2(row.balance + num(invoice.balance));
    map.set(key, row);
  }

  const rows = [...map.values()].sort((a, b) => b.total - a.total);
  return {
    from,
    to,
    totals: {
      salespeople: rows.length,
      invoices: rows.reduce((sum, row) => sum + row.invoices, 0),
      total: round2(rows.reduce((sum, row) => sum + row.total, 0)),
      paid: round2(rows.reduce((sum, row) => sum + row.paid, 0)),
      balance: round2(rows.reduce((sum, row) => sum + row.balance, 0)),
    },
    rows,
  };
}

// ---------------------------------------------------------------------------
// Purchases by supplier
// ---------------------------------------------------------------------------

export async function buildPurchasesBySupplier(fromInput?: Date, toInput?: Date) {
  const { from, to } = resolveRange(fromInput, toInput);
  const orders = await prisma.purchaseOrder.findMany({
    where: {
      orderDate: { gte: from, lte: to },
      status: { not: 'CANCELLED' },
    },
    select: {
      total: true,
      supplierId: true,
      supplier: { select: { name: true, balance: true } },
      lines: { select: { receivedQty: true, unitCost: true } },
    },
  });

  const map = new Map<
    string,
    {
      supplierId: string;
      supplierName: string;
      orders: number;
      total: number;
      receivedValue: number;
      balance: number;
    }
  >();
  for (const order of orders) {
    const row =
      map.get(order.supplierId) ??
      {
        supplierId: order.supplierId,
        supplierName: order.supplier?.name ?? '',
        orders: 0,
        total: 0,
        receivedValue: 0,
        balance: num(order.supplier?.balance),
      };
    row.orders += 1;
    row.total = round2(row.total + num(order.total));
    row.receivedValue = round2(
      row.receivedValue +
        order.lines.reduce(
          (sum, line) => sum + line.receivedQty * num(line.unitCost),
          0,
        ),
    );
    map.set(order.supplierId, row);
  }

  const rows = [...map.values()].sort((a, b) => b.total - a.total);
  return {
    from,
    to,
    totals: {
      suppliers: rows.length,
      orders: rows.reduce((sum, row) => sum + row.orders, 0),
      total: round2(rows.reduce((sum, row) => sum + row.total, 0)),
      receivedValue: round2(
        rows.reduce((sum, row) => sum + row.receivedValue, 0),
      ),
      balance: round2(rows.reduce((sum, row) => sum + row.balance, 0)),
    },
    rows,
  };
}

// ---------------------------------------------------------------------------
// Returns (customer + supplier)
// ---------------------------------------------------------------------------

export async function buildReturnsReport(
  fromInput?: Date,
  toInput?: Date,
  type?: string,
  user?: ScopeUser,
) {
  const { from, to } = resolveRange(fromInput, toInput);
  const returns = await prisma.returnOrder.findMany({
    where: {
      returnDate: { gte: from, lte: to },
      ...(user && isSalesperson(user) ? { customer: { salespersonId: user.id } } : {}),
      ...(type === 'CUSTOMER_RETURN' || type === 'SUPPLIER_RETURN'
        ? { type: type as 'CUSTOMER_RETURN' | 'SUPPLIER_RETURN' }
        : {}),
    },
    orderBy: { returnDate: 'desc' },
    include: {
      customer: { select: { name: true } },
      supplier: { select: { name: true } },
      _count: { select: { lines: true } },
    },
  });

  const rows = returns.map((row) => ({
    id: row.id,
    number: row.number,
    type: row.type,
    date: row.returnDate.toISOString(),
    partyName:
      row.type === 'CUSTOMER_RETURN'
        ? row.customer?.name ?? ''
        : row.supplier?.name ?? '',
    lines: row._count.lines,
    status: row.status,
    total: num(row.total),
  }));

  const customerTotal = round2(
    rows
      .filter((row) => row.type === 'CUSTOMER_RETURN')
      .reduce((sum, row) => sum + row.total, 0),
  );
  const supplierTotal = round2(
    rows
      .filter((row) => row.type === 'SUPPLIER_RETURN')
      .reduce((sum, row) => sum + row.total, 0),
  );

  return {
    from,
    to,
    totals: {
      count: rows.length,
      total: round2(customerTotal + supplierTotal),
      customerTotal,
      supplierTotal,
    },
    rows,
  };
}

// ---------------------------------------------------------------------------
// Cash flow per cash box
// ---------------------------------------------------------------------------

export async function buildCashFlowReport(fromInput?: Date, toInput?: Date) {
  const { from, to } = resolveRange(fromInput, toInput);
  const boxes = await prisma.cashBox.findMany({ orderBy: { code: 'asc' } });

  const rows = await Promise.all(
    boxes.map(async (box) => {
      const [
        openingPaymentsIn,
        openingPaymentsOut,
        openingExpenses,
        openingTransfersIn,
        openingTransfersOut,
        periodPaymentsIn,
        periodPaymentsOut,
        periodExpenses,
        periodTransfersIn,
        periodTransfersOut,
      ] = await Promise.all([
        prisma.payment.aggregate({
          where: {
            cashBoxId: box.id,
            direction: 'INBOUND',
            paidAt: { lt: from },
            cancelledAt: null,
          },
          _sum: { amount: true },
        }),
        prisma.payment.aggregate({
          where: {
            cashBoxId: box.id,
            direction: 'OUTBOUND',
            paidAt: { lt: from },
            cancelledAt: null,
          },
          _sum: { amount: true },
        }),
        prisma.expense.aggregate({
          where: { cashBoxId: box.id, spentAt: { lt: from }, cancelledAt: null },
          _sum: { amount: true },
        }),
        prisma.cashTransfer.aggregate({
          where: {
            toBoxId: box.id,
            transferDate: { lt: from },
            cancelledAt: null,
          },
          _sum: { amount: true },
        }),
        prisma.cashTransfer.aggregate({
          where: {
            fromBoxId: box.id,
            transferDate: { lt: from },
            cancelledAt: null,
          },
          _sum: { amount: true },
        }),
        prisma.payment.aggregate({
          where: {
            cashBoxId: box.id,
            direction: 'INBOUND',
            paidAt: { gte: from, lte: to },
            cancelledAt: null,
          },
          _sum: { amount: true },
        }),
        prisma.payment.aggregate({
          where: {
            cashBoxId: box.id,
            direction: 'OUTBOUND',
            paidAt: { gte: from, lte: to },
            cancelledAt: null,
          },
          _sum: { amount: true },
        }),
        prisma.expense.aggregate({
          where: {
            cashBoxId: box.id,
            spentAt: { gte: from, lte: to },
            cancelledAt: null,
          },
          _sum: { amount: true },
        }),
        prisma.cashTransfer.aggregate({
          where: {
            toBoxId: box.id,
            transferDate: { gte: from, lte: to },
            cancelledAt: null,
          },
          _sum: { amount: true },
        }),
        prisma.cashTransfer.aggregate({
          where: {
            fromBoxId: box.id,
            transferDate: { gte: from, lte: to },
            cancelledAt: null,
          },
          _sum: { amount: true },
        }),
      ]);

      const opening = round2(
        num(box.openingBalance) +
          num(openingPaymentsIn._sum.amount) -
          num(openingPaymentsOut._sum.amount) -
          num(openingExpenses._sum.amount) +
          num(openingTransfersIn._sum.amount) -
          num(openingTransfersOut._sum.amount),
      );
      const inTotal = round2(
        num(periodPaymentsIn._sum.amount) + num(periodTransfersIn._sum.amount),
      );
      const outTotal = round2(
        num(periodPaymentsOut._sum.amount) +
          num(periodExpenses._sum.amount) +
          num(periodTransfersOut._sum.amount),
      );
      return {
        cashBoxId: box.id,
        cashBoxName: box.name,
        code: box.code,
        opening,
        inTotal,
        outTotal,
        net: round2(inTotal - outTotal),
        closing: round2(opening + inTotal - outTotal),
      };
    }),
  );

  return {
    from,
    to,
    totals: {
      boxes: rows.length,
      opening: round2(rows.reduce((sum, row) => sum + row.opening, 0)),
      inTotal: round2(rows.reduce((sum, row) => sum + row.inTotal, 0)),
      outTotal: round2(rows.reduce((sum, row) => sum + row.outTotal, 0)),
      net: round2(rows.reduce((sum, row) => sum + row.net, 0)),
      closing: round2(rows.reduce((sum, row) => sum + row.closing, 0)),
    },
    rows,
  };
}

// ---------------------------------------------------------------------------
// Dead / slow-moving stock
// ---------------------------------------------------------------------------

export async function buildDeadStockReport(daysInput?: number) {
  const days =
    Number.isFinite(daysInput) && (daysInput as number) > 0
      ? Math.floor(daysInput as number)
      : 90;
  const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  const now = new Date();

  const [levels, lastSales] = await Promise.all([
    prisma.stockLevel.findMany({
      where: { quantity: { gt: 0 } },
      include: {
        product: {
          select: {
            id: true,
            sku: true,
            name: true,
            costPrice: true,
            salePrice: true,
            category: { select: { name: true } },
          },
        },
      },
    }),
    prisma.stockMovement.groupBy({
      by: ['productId'],
      where: { type: 'SALE' },
      _max: { createdAt: true },
    }),
  ]);

  const lastSaleByProduct = new Map<string, Date>();
  for (const row of lastSales) {
    if (row._max.createdAt) {
      lastSaleByProduct.set(row.productId, row._max.createdAt);
    }
  }

  const byProduct = new Map<
    string,
    {
      productId: string;
      sku: string;
      name: string;
      categoryName: string;
      quantity: number;
      costValue: number;
      retailValue: number;
      lastSaleAt: string | null;
      daysSince: number | null;
    }
  >();
  for (const level of levels) {
    const lastSale = lastSaleByProduct.get(level.productId) ?? null;
    if (lastSale && lastSale >= cutoff) continue;
    const current =
      byProduct.get(level.productId) ??
      {
        productId: level.productId,
        sku: level.product.sku,
        name: level.product.name,
        categoryName: level.product.category?.name ?? '',
        quantity: 0,
        costValue: 0,
        retailValue: 0,
        lastSaleAt: lastSale ? lastSale.toISOString() : null,
        daysSince: lastSale
          ? Math.floor((now.getTime() - lastSale.getTime()) / 86_400_000)
          : null,
      };
    current.quantity += level.quantity;
    current.costValue = round2(
      current.costValue + level.quantity * num(level.product.costPrice),
    );
    current.retailValue = round2(
      current.retailValue + level.quantity * num(level.product.salePrice),
    );
    byProduct.set(level.productId, current);
  }

  const rows = [...byProduct.values()].sort((a, b) => b.costValue - a.costValue);
  return {
    days,
    cutoff,
    totals: {
      items: rows.length,
      units: rows.reduce((sum, row) => sum + row.quantity, 0),
      costValue: round2(rows.reduce((sum, row) => sum + row.costValue, 0)),
      retailValue: round2(rows.reduce((sum, row) => sum + row.retailValue, 0)),
    },
    rows,
  };
}

// ---------------------------------------------------------------------------
// Payments by method
// ---------------------------------------------------------------------------

const PAYMENT_METHODS = [
  'CASH',
  'CARD',
  'BANK_TRANSFER',
  'MOBILE_MONEY',
  'CHEQUE',
  'OTHER',
] as const;

export async function buildPaymentsByMethod(
  fromInput?: Date,
  toInput?: Date,
) {
  const { from, to } = resolveRange(fromInput, toInput);
  const payments = await prisma.payment.findMany({
    where: {
      paidAt: { gte: from, lte: to },
      cancelledAt: null,
    },
    select: { method: true, direction: true, amount: true },
  });

  const map = new Map(
    PAYMENT_METHODS.map((method) => [
      method,
      { method, count: 0, inTotal: 0, outTotal: 0, net: 0 },
    ]),
  );
  for (const payment of payments) {
    const row = map.get(payment.method as (typeof PAYMENT_METHODS)[number]);
    if (!row) continue;
    row.count += 1;
    const amount = num(payment.amount);
    if (payment.direction === 'INBOUND') row.inTotal = round2(row.inTotal + amount);
    else row.outTotal = round2(row.outTotal + amount);
    row.net = round2(row.inTotal - row.outTotal);
  }

  const rows = [...map.values()].filter((row) => row.count > 0);
  return {
    from,
    to,
    totals: {
      count: rows.reduce((sum, row) => sum + row.count, 0),
      inTotal: round2(rows.reduce((sum, row) => sum + row.inTotal, 0)),
      outTotal: round2(rows.reduce((sum, row) => sum + row.outTotal, 0)),
      net: round2(rows.reduce((sum, row) => sum + row.net, 0)),
    },
    rows,
  };
}
