import { Prisma } from '@prisma/client';
import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { dayKey } from './reports.service';

// ---------------------------------------------------------------------------
// Salespeople reports (تقارير المناديب)
// ---------------------------------------------------------------------------
//
// A salesperson (مندوب) is a user who is allowed to sell. A sale is attributed
// to a representative in this order — the same rule the receivables report uses:
//
//   1. the representative assigned to the invoice's customer, otherwise
//   2. the user who created the sales order behind the invoice.
//
// Sales quantities come from the *fulfilled* quantities of non-cancelled sales
// orders, i.e. what actually left the warehouse.

interface RepRef {
  id: string;
  name: string;
}

/** Resolves the representative of an invoice/customer/order combination. */
function resolveRep(
  customer: { salesperson: RepRef | null } | null,
  order: { userId: string | null; user: RepRef | null } | null,
): RepRef | null {
  return customer?.salesperson ?? order?.user ?? null;
}

// ---------------------------------------------------------------------------
// 1) Consolidated sales note per salesperson (إذن مجمع للمبيعات)
// ---------------------------------------------------------------------------

export interface ConsolidatedLine {
  productId: string;
  sku: string;
  name: string;
  unit: string;
  quantity: number;
  net: number;
}

export interface ConsolidatedOrderRow {
  id: string;
  number: string;
  orderDate: string;
  customer: string | null;
  quantity: number;
  net: number;
}

export interface ConsolidatedSalesperson {
  salespersonId: string | null;
  salesperson: string | null;
  orders: number;
  quantity: number;
  net: number;
  lines: ConsolidatedLine[];
  orderRows: ConsolidatedOrderRow[];
}

export interface ConsolidatedSalesNote {
  from: string;
  to: string;
  totals: { salespeople: number; orders: number; quantity: number; net: number };
  rows: ConsolidatedSalesperson[];
}

/**
 * Consolidated sale note: per salesperson, the fulfilled quantities of every
 * product sold in the period, plus the supporting order list.
 */
export async function buildConsolidatedSalesNote(
  fromInput?: Date,
  toInput?: Date,
  salespersonId?: string,
): Promise<ConsolidatedSalesNote> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
  const to = toInput ?? now;

  const where: Prisma.SalesOrderWhereInput = {
    orderDate: { gte: from, lte: to },
    status: { in: ['PARTIALLY_FULFILLED', 'FULFILLED'] },
  };
  if (salespersonId) {
    where.OR = [
      { customer: { salespersonId } },
      { userId: salespersonId },
    ];
  }

  const orders = await prisma.salesOrder.findMany({
    where,
    select: {
      id: true,
      number: true,
      orderDate: true,
      userId: true,
      customer: {
        select: {
          name: true,
          salesperson: { select: { id: true, name: true } },
        },
      },
      user: { select: { id: true, name: true } },
      lines: {
        select: {
          productId: true,
          fulfilledQty: true,
          unitPrice: true,
          discount: true,
          quantity: true,
          product: { select: { sku: true, name: true, unit: true } },
        },
      },
    },
    orderBy: { orderDate: 'asc' },
  });

  const byRep = new Map<string, ConsolidatedSalesperson>();

  for (const order of orders) {
    // Fulfilled quantity is what actually moved; fall back to nothing when the
    // order has no fulfilled line at all.
    const fulfilledLines = order.lines.filter((line) => line.fulfilledQty > 0);
    if (fulfilledLines.length === 0) continue;

    const rep = resolveRep(order.customer, order);
    const key = rep?.id ?? '-';
    const row =
      byRep.get(key) ??
      ({
        salespersonId: rep?.id ?? null,
        salesperson: rep?.name ?? null,
        orders: 0,
        quantity: 0,
        net: 0,
        lines: [],
        orderRows: [],
      } satisfies ConsolidatedSalesperson);

    // Distribute a line's discount proportionally to what was fulfilled.
    const lineMap = new Map<string, ConsolidatedLine>();
    let orderQuantity = 0;
    let orderNet = 0;

    for (const line of fulfilledLines) {
      const share = Math.min(1, line.fulfilledQty / (line.quantity || 1));
      const discount = round2(Number(line.discount) * share);
      const net = Math.max(0, round2(line.fulfilledQty * Number(line.unitPrice) - discount));
      orderQuantity += line.fulfilledQty;
      orderNet += net;

      const entry =
        lineMap.get(line.productId) ??
        ({
          productId: line.productId,
          sku: line.product?.sku ?? '',
          name: line.product?.name ?? '',
          unit: line.product?.unit ?? '',
          quantity: 0,
          net: 0,
        } satisfies ConsolidatedLine);
      entry.quantity += line.fulfilledQty;
      entry.net = round2(entry.net + net);
      lineMap.set(line.productId, entry);
    }

    row.orders += 1;
    row.quantity += orderQuantity;
    row.net = round2(row.net + orderNet);
    row.orderRows.push({
      id: order.id,
      number: order.number,
      orderDate: dayKey(order.orderDate),
      customer: order.customer?.name ?? null,
      quantity: orderQuantity,
      net: round2(orderNet),
    });

    // Merge this order's product lines into the salesperson's consolidated list.
    for (const entry of lineMap.values()) {
      const existing = row.lines.find((line) => line.productId === entry.productId);
      if (existing) {
        existing.quantity += entry.quantity;
        existing.net = round2(existing.net + entry.net);
      } else {
        row.lines.push({ ...entry });
      }
    }
    byRep.set(key, row);
  }

  // Subtract posted customer returns from each salesperson's net sales.
  const returns = await prisma.returnOrder.findMany({
    where: {
      type: 'CUSTOMER_RETURN',
      status: 'POSTED',
      returnDate: { gte: from, lte: to },
    },
    select: {
      total: true,
      customer: { select: { salespersonId: true } },
      lines: { select: { productId: true, quantity: true, unitPrice: true } },
    },
  });
  for (const ret of returns) {
    const spId = ret.customer?.salespersonId;
    if (!spId) continue;
    const row = byRep.get(spId);
    if (!row) continue;
    let returnNet = 0;
    for (const l of ret.lines) {
      const lineNet = round2(l.quantity * Number(l.unitPrice));
      returnNet = round2(returnNet + lineNet);
      const existing = row.lines.find((x) => x.productId === l.productId);
      if (existing) {
        existing.quantity = Math.max(0, existing.quantity - l.quantity);
        existing.net = round2(Math.max(0, existing.net - lineNet));
      }
    }
    row.net = round2(Math.max(0, row.net - (returnNet > 0 ? returnNet : Number(ret.total))));
    row.quantity = Math.max(0, row.quantity - ret.lines.reduce((s, l) => s + l.quantity, 0));
  }

  const rows = [...byRep.values()]
    .map((row) => ({
      ...row,
      lines: row.lines.sort((a, b) => b.quantity - a.quantity),
    }))
    .sort((a, b) => (a.salesperson ?? '').localeCompare(b.salesperson ?? ''));

  return {
    from: dayKey(from),
    to: dayKey(to),
    totals: rows.reduce(
      (acc, row) => ({
        salespeople: acc.salespeople + 1,
        orders: acc.orders + row.orders,
        quantity: acc.quantity + row.quantity,
        net: round2(acc.net + row.net),
      }),
      { salespeople: 0, orders: 0, quantity: 0, net: 0 },
    ),
    rows,
  };
}

// ---------------------------------------------------------------------------
// 2) Profitability per salesperson (ربحية كل مندوب)
// ---------------------------------------------------------------------------

export interface SalespersonProfitLine {
  productId: string;
  sku: string;
  name: string;
  quantity: number;
  revenue: number;
  cost: number;
  profit: number;
}

export interface SalespersonProfitRow {
  salespersonId: string | null;
  salesperson: string | null;
  orders: number;
  quantity: number;
  revenue: number;
  cost: number;
  profit: number;
  margin: number;
  lines: SalespersonProfitLine[];
}

export interface SalespersonProfitReport {
  from: string;
  to: string;
  totals: {
    salespeople: number;
    revenue: number;
    cost: number;
    profit: number;
    margin: number;
  };
  rows: SalespersonProfitRow[];
}

/** Revenue (net of discount, excl. tax) minus product cost, per salesperson. */
export async function buildProfitBySalesperson(
  fromInput?: Date,
  toInput?: Date,
  salespersonId?: string,
): Promise<SalespersonProfitReport> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
  const to = toInput ?? now;

  const where: Prisma.InvoiceWhereInput = {
    status: { notIn: ['DRAFT', 'VOID'] },
    issueDate: { gte: from, lte: to },
  };
  if (salespersonId) {
    where.OR = [
      { customer: { salespersonId } },
      { salesOrder: { userId: salespersonId } },
    ];
  }

  const invoices = await prisma.invoice.findMany({
    where,
    select: {
      id: true,
      customer: {
        select: {
          salesperson: { select: { id: true, name: true } },
        },
      },
      salesOrder: { select: { userId: true, user: { select: { id: true, name: true } } } },
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

  const byRep = new Map<string, SalespersonProfitRow>();

  for (const invoice of invoices) {
    const rep = resolveRep(invoice.customer, invoice.salesOrder);
    const key = rep?.id ?? '-';
    const row =
      byRep.get(key) ??
      ({
        salespersonId: rep?.id ?? null,
        salesperson: rep?.name ?? null,
        orders: 0,
        quantity: 0,
        revenue: 0,
        cost: 0,
        profit: 0,
        margin: 0,
        lines: [],
      } satisfies SalespersonProfitRow);

    row.orders += 1;

    for (const line of invoice.lines) {
      const net = Math.max(
        0,
        round2(line.quantity * Number(line.unitPrice) - Number(line.discount)),
      );
      const unitCost =
        Number(line.unitCost) ||
        (line.product ? Number(line.product.costPrice) : 0);
      const lineCost = round2(line.quantity * unitCost);
      row.quantity += line.quantity;
      row.revenue = round2(row.revenue + net);
      row.cost = round2(row.cost + lineCost);

      if (!line.productId || !line.product) continue;
      const entry = row.lines.find((item) => item.productId === line.productId);
      if (entry) {
        entry.quantity += line.quantity;
        entry.revenue = round2(entry.revenue + net);
        entry.cost = round2(entry.cost + lineCost);
        entry.profit = round2(entry.revenue - entry.cost);
      } else {
        row.lines.push({
          productId: line.productId,
          sku: line.product.sku,
          name: line.product.name,
          quantity: line.quantity,
          revenue: net,
          cost: lineCost,
          profit: round2(net - lineCost),
        });
      }
    }
    byRep.set(key, row);
  }

  const rows = [...byRep.values()].map((row) => {
    const profit = round2(row.revenue - row.cost);
    return {
      ...row,
      profit,
      margin: row.revenue > 0 ? round2((profit / row.revenue) * 100) : 0,
      lines: row.lines.sort((a, b) => b.profit - a.profit),
    };
  });
  rows.sort((a, b) => b.profit - a.profit);

  const revenue = round2(rows.reduce((sum, row) => sum + row.revenue, 0));
  const cost = round2(rows.reduce((sum, row) => sum + row.cost, 0));
  const profit = round2(revenue - cost);

  return {
    from: dayKey(from),
    to: dayKey(to),
    totals: {
      salespeople: rows.length,
      revenue,
      cost,
      profit,
      margin: revenue > 0 ? round2((profit / revenue) * 100) : 0,
    },
    rows,
  };
}

// ---------------------------------------------------------------------------
// 3) Collections per salesperson (تحصيلات كل مندوب)
// ---------------------------------------------------------------------------

export interface SalespersonCollectionCustomer {
  customerId: string | null;
  customer: string | null;
  amount: number;
}

export interface SalespersonCollectionsRow {
  salespersonId: string | null;
  salesperson: string | null;
  vouchers: number;
  amount: number;
  customers: SalespersonCollectionCustomer[];
}

export interface SalespersonCollectionsReport {
  from: string;
  to: string;
  totals: { salespeople: number; vouchers: number; amount: number };
  rows: SalespersonCollectionsRow[];
}

/** Cash collected from customers by each salesperson within the period. */
export async function buildCollectionsBySalesperson(
  fromInput?: Date,
  toInput?: Date,
  salespersonId?: string,
): Promise<SalespersonCollectionsReport> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
  const to = toInput ?? now;

  const vouchers = await prisma.collectionVoucher.findMany({
    where: {
      cancelledAt: null,
      collectedAt: { gte: from, lte: to },
      ...(salespersonId ? { salespersonId } : {}),
    },
    select: {
      id: true,
      total: true,
      salesperson: { select: { id: true, name: true } },
      lines: {
        select: {
          amount: true,
          customer: { select: { id: true, name: true } },
        },
      },
    },
  });

  const byRep = new Map<string, SalespersonCollectionsRow>();

  for (const voucher of vouchers) {
    const rep = voucher.salesperson;
    const key = rep?.id ?? '-';
    const row =
      byRep.get(key) ??
      ({
        salespersonId: rep?.id ?? null,
        salesperson: rep?.name ?? null,
        vouchers: 0,
        amount: 0,
        customers: [],
      } satisfies SalespersonCollectionsRow);

    row.vouchers += 1;

    // Lines carry the per-customer breakdown; a voucher without lines still
    // counts towards the total (kept on the voucher itself).
    if (voucher.lines.length === 0) {
      row.amount = round2(row.amount + Number(voucher.total));
    }
    for (const line of voucher.lines) {
      const amount = Number(line.amount);
      row.amount = round2(row.amount + amount);
      const customerId = line.customer?.id ?? null;
      const entry = row.customers.find((item) => item.customerId === customerId);
      if (entry) {
        entry.amount = round2(entry.amount + amount);
      } else {
        row.customers.push({
          customerId,
          customer: line.customer?.name ?? null,
          amount: round2(amount),
        });
      }
    }
    byRep.set(key, row);
  }

  const rows = [...byRep.values()]
    .map((row) => ({
      ...row,
      customers: row.customers.sort((a, b) => b.amount - a.amount),
    }))
    .sort((a, b) => b.amount - a.amount);

  return {
    from: dayKey(from),
    to: dayKey(to),
    totals: {
      salespeople: rows.length,
      vouchers: rows.reduce((sum, row) => sum + row.vouchers, 0),
      amount: round2(rows.reduce((sum, row) => sum + row.amount, 0)),
    },
    rows,
  };
}

// ---------------------------------------------------------------------------
// 4) Detailed salesperson statement (كشف حساب مندوب)
// ---------------------------------------------------------------------------

export interface SalespersonStatementRow {
  date: string;
  type: 'SALE' | 'COLLECTION';
  reference: string;
  customer: string | null;
  debit: number;
  credit: number;
  balance: number;
}

export interface SalespersonStatement {
  salesperson: { id: string; name: string };
  from: string;
  to: string;
  openingBalance: number;
  totals: { sales: number; collections: number; closingBalance: number };
  rows: SalespersonStatementRow[];
  byProduct: ConsolidatedLine[];
}

/**
 * A single salesperson's account: what they sold on credit (debit) against what
 * they collected (credit), in date order with a running balance.
 */
export async function buildSalespersonStatement(
  salespersonId: string,
  fromInput?: Date,
  toInput?: Date,
): Promise<SalespersonStatement> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
  const to = toInput ?? now;

  const salesperson = await prisma.user.findUnique({
    where: { id: salespersonId },
    select: { id: true, name: true },
  });
  if (!salesperson) {
    // Caller turns this into a 404; a throw keeps the service honest.
    throw new Error('SALESPERSON_NOT_FOUND');
  }

  const [invoices, vouchers] = await Promise.all([
    prisma.invoice.findMany({
      where: {
        status: { notIn: ['DRAFT', 'VOID'] },
        issueDate: { lte: to },
        OR: [
          { customer: { salespersonId } },
          { salesOrder: { userId: salespersonId } },
        ],
      },
      select: {
        number: true,
        issueDate: true,
        total: true,
        customer: { select: { name: true } },
      },
    }),
    prisma.collectionVoucher.findMany({
      where: { salespersonId, cancelledAt: null, collectedAt: { lte: to } },
      select: {
        number: true,
        collectedAt: true,
        total: true,
        lines: {
          select: { amount: true, customer: { select: { name: true } } },
        },
      },
    }),
  ]);

  const movements: SalespersonStatementRow[] = [];

  for (const invoice of invoices) {
    const date = dayKey(invoice.issueDate);
    movements.push({
      date,
      type: 'SALE',
      reference: invoice.number,
      customer: invoice.customer?.name ?? null,
      debit: round2(Number(invoice.total)),
      credit: 0,
      balance: 0,
    });
  }

  for (const voucher of vouchers) {
    const date = dayKey(voucher.collectedAt);
    const amount =
      voucher.lines.length > 0
        ? round2(voucher.lines.reduce((sum, line) => sum + Number(line.amount), 0))
        : round2(Number(voucher.total));
    const customers = voucher.lines
      .map((line) => line.customer?.name)
      .filter((name): name is string => Boolean(name));
    movements.push({
      date,
      type: 'COLLECTION',
      reference: voucher.number,
      customer: [...new Set(customers)].join(', ') || null,
      debit: 0,
      credit: amount,
      balance: 0,
    });
  }

  movements.sort(
    (a, b) => a.date.localeCompare(b.date) || a.reference.localeCompare(b.reference),
  );

  // Opening balance = everything that happened before the period start.
  const openingBalance = round2(
    movements
      .filter((row) => row.date < dayKey(from))
      .reduce((sum, row) => sum + row.debit - row.credit, 0),
  );

  let running = openingBalance;
  let sales = 0;
  let collections = 0;
  const rows: SalespersonStatementRow[] = [];
  for (const movement of movements) {
    if (movement.date < dayKey(from)) continue; // folded into the opening balance
    running = round2(running + movement.debit - movement.credit);
    sales = round2(sales + movement.debit);
    collections = round2(collections + movement.credit);
    rows.push({ ...movement, balance: running });
  }

  // Product mix for the period (reuses the consolidated note logic). Pick the
  // row that actually belongs to this salesperson — a customer may carry a
  // different representative, in which case the note would hold more than one.
  const note = await buildConsolidatedSalesNote(from, to, salespersonId);
  const ownRow =
    note.rows.find((row) => row.salespersonId === salespersonId) ?? note.rows[0];

  return {
    salesperson,
    from: dayKey(from),
    to: dayKey(to),
    openingBalance,
    totals: { sales, collections, closingBalance: running },
    rows,
    byProduct: ownRow?.lines ?? [],
  };
}

// ---------------------------------------------------------------------------
// Salesperson customer debt table (مديونية مناديب العملاء)
// ---------------------------------------------------------------------------

export interface SalespersonCustomerRow {
  customerId: string;
  customer: string;
  phone: string | null;
  /** Balance carried in before the period start (opening). */
  previous: number;
  /** Invoices issued during the period. */
  debit: number;
  /** Collections received during the period. */
  credit: number;
  /** previous + debit − credit. */
  balance: number;
}

export type CustomerDebtFilter = 'all' | 'debtors' | 'creditors';

export interface SalespersonCustomerDebt {
  salesperson: { id: string; name: string };
  from: string;
  to: string;
  filter: CustomerDebtFilter;
  rows: SalespersonCustomerRow[];
  totals: {
    previous: number;
    debit: number;
    credit: number;
    balance: number;
  };
}

/**
 * One row per customer handled by a salesperson, in the classic ledger shape:
 * `# | customer | previous | debit | credit | balance`.
 *
 * Sales come from issued invoices, collections from non-cancelled vouchers,
 * and the "previous" column is whatever balance existed before the period.
 */
export async function buildSalespersonCustomerDebt(
  salespersonId: string,
  fromInput?: Date,
  toInput?: Date,
  filter: CustomerDebtFilter = 'all',
): Promise<SalespersonCustomerDebt> {
  const now = new Date();
  const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
  const to = toInput ?? now;
  const fromKey = dayKey(from);
  const toKey = dayKey(to);

  const salesperson = await prisma.user.findUnique({
    where: { id: salespersonId },
    select: { id: true, name: true },
  });
  if (!salesperson) throw new Error('SALESPERSON_NOT_FOUND');

  // Every account that belongs to this salesperson: assigned directly, invoiced
  // under one of their orders, or collected by them. Seeding from the customer
  // row is what makes carried opening balances show up even when the account
  // has no invoice or collection inside the selected period.
  const customers = await prisma.customer.findMany({
    where: {
      OR: [
        { salespersonId },
        {
          invoices: {
            some: {
              status: { notIn: ['DRAFT', 'VOID'] },
              salesOrder: { userId: salespersonId },
            },
          },
        },
        { collectionLines: { some: { collection: { salespersonId } } } },
      ],
    },
    select: { id: true, name: true, phone: true, balance: true },
  });
  const customerIds = customers.map((customer) => customer.id);

  const [invoices, payments, returns, settlements, walkInInvoices] = await Promise.all([
    customerIds.length === 0
      ? Promise.resolve([])
      : prisma.invoice.findMany({
          where: {
            customerId: { in: customerIds },
            status: { notIn: ['DRAFT', 'VOID'] },
            issueDate: { gte: from, lte: to },
          },
          select: { customerId: true, total: true },
        }),
    customerIds.length === 0
      ? Promise.resolve([])
      : prisma.payment.findMany({
          where: {
            customerId: { in: customerIds },
            direction: 'INBOUND',
            cancelledAt: null,
            paidAt: { gte: from, lte: to },
          },
          select: { customerId: true, amount: true },
        }),
    customerIds.length === 0
      ? Promise.resolve([])
      : prisma.returnOrder.findMany({
          where: {
            customerId: { in: customerIds },
            type: 'CUSTOMER_RETURN',
            status: 'POSTED',
            returnDate: { gte: from, lte: to },
          },
          select: { customerId: true, total: true },
        }),
    customerIds.length === 0
      ? Promise.resolve([])
      : prisma.accountSettlement.findMany({
          where: {
            customerId: { in: customerIds },
            target: 'CUSTOMER',
            cancelledAt: null,
            settledAt: { gte: from, lte: to },
          },
          select: { customerId: true, direction: true, amount: true },
        }),
    prisma.invoice.findMany({
      where: {
        customerId: null,
        status: { notIn: ['DRAFT', 'VOID'] },
        issueDate: { lte: to },
        salesOrder: { userId: salespersonId },
      },
      select: { issueDate: true, total: true, balance: true },
    }),
  ]);

  interface Bucket {
    customerId: string;
    customer: string;
    phone: string | null;
    previous: number;
    debit: number;
    credit: number;
  }
  const map = new Map<string, Bucket>();
  for (const customer of customers) {
    map.set(customer.id, {
      customerId: customer.id,
      customer: customer.name,
      phone: customer.phone,
      previous: 0,
      debit: 0,
      credit: 0,
    });
  }

  const debitByCustomer = new Map<string, number>();
  for (const invoice of invoices) {
    if (!invoice.customerId) continue;
    debitByCustomer.set(
      invoice.customerId,
      round2((debitByCustomer.get(invoice.customerId) ?? 0) + Number(invoice.total)),
    );
  }

  const creditByCustomer = new Map<string, number>();
  for (const payment of payments) {
    if (!payment.customerId) continue;
    creditByCustomer.set(
      payment.customerId,
      round2((creditByCustomer.get(payment.customerId) ?? 0) + Number(payment.amount)),
    );
  }

  // Returns and settlements move the balance too, so they must appear in the
  // period columns instead of being folded into "previous".
  for (const order of returns) {
    if (!order.customerId) continue;
    creditByCustomer.set(
      order.customerId,
      round2((creditByCustomer.get(order.customerId) ?? 0) + Number(order.total)),
    );
  }

  for (const settlement of settlements) {
    if (!settlement.customerId) continue;
    const amount = Number(settlement.amount);
    if (settlement.direction === 'INCREASE') {
      debitByCustomer.set(
        settlement.customerId,
        round2((debitByCustomer.get(settlement.customerId) ?? 0) + amount),
      );
    } else {
      creditByCustomer.set(
        settlement.customerId,
        round2((creditByCustomer.get(settlement.customerId) ?? 0) + amount),
      );
    }
  }

  const rows: SalespersonCustomerRow[] = [];
  for (const customer of customers) {
    const debit = debitByCustomer.get(customer.id) ?? 0;
    const credit = creditByCustomer.get(customer.id) ?? 0;
    // The stored balance is authoritative. Walking it backwards through this
    // period's movements gives the balance the customer carried in, including
    // any migration/opening balance that has no invoice behind it.
    const closing = round2(Number(customer.balance));
    const previous = round2(closing - debit + credit);
    if (filter === 'debtors' && closing <= 0) continue;
    if (filter === 'creditors' && closing >= 0) continue;
    rows.push({
      customerId: customer.id,
      customer: customer.name,
      phone: customer.phone,
      previous,
      debit,
      credit,
      balance: closing,
    });
  }

  // Walk-in invoices have no customer row to carry a balance; their outstanding
  // invoice balances are the closest equivalent.
  let walkInPrevious = 0;
  let walkInDebit = 0;
  let walkInClosing = 0;
  for (const invoice of walkInInvoices) {
    const key = dayKey(invoice.issueDate);
    walkInClosing = round2(walkInClosing + Number(invoice.balance));
    if (key >= fromKey) walkInDebit = round2(walkInDebit + Number(invoice.total));
  }
  walkInPrevious = round2(walkInClosing - walkInDebit);
  const walkInVisible =
    filter === 'all'
      ? walkInPrevious !== 0 || walkInDebit !== 0
      : filter === 'debtors'
        ? walkInClosing > 0
        : walkInClosing < 0;
  if (walkInVisible) {
    rows.push({
      customerId: 'walk-in',
      customer: 'Walk-in',
      phone: null,
      previous: walkInPrevious,
      debit: walkInDebit,
      credit: 0,
      balance: walkInClosing,
    });
  }

  rows.sort((a, b) => b.balance - a.balance || a.customer.localeCompare(b.customer));

  const totals = rows.reduce(
    (acc, row) => ({
      previous: round2(acc.previous + row.previous),
      debit: round2(acc.debit + row.debit),
      credit: round2(acc.credit + row.credit),
      balance: round2(acc.balance + row.balance),
    }),
    { previous: 0, debit: 0, credit: 0, balance: 0 },
  );

  return { salesperson, from: fromKey, to: toKey, filter, rows, totals };
}
