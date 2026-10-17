import { ApiError } from '../../lib/api-error';
import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';

export type StatementRowType = 'INVOICE' | 'PAYMENT' | 'PURCHASE_ORDER';

export interface StatementRow {
  /** ISO timestamp of the accounting event. */
  date: string;
  type: StatementRowType;
  number: string;
  description: string;
  debit: number;
  credit: number;
  balance: number;
}

export interface StatementTotals {
  debit: number;
  credit: number;
  closingBalance: number;
}

export interface StatementCustomer {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
  address: string | null;
  balance: number;
  creditLimit: number;
}

export interface StatementSupplier {
  id: string;
  name: string;
  contact: string | null;
  email: string | null;
  phone: string | null;
  address: string | null;
  balance: number;
  paymentTermDays: number;
}

export interface CustomerStatement {
  customer: StatementCustomer;
  from: string | null;
  to: string | null;
  openingBalance: number;
  rows: StatementRow[];
  totals: StatementTotals;
}

export interface SupplierStatement {
  supplier: StatementSupplier;
  from: string | null;
  to: string | null;
  openingBalance: number;
  rows: StatementRow[];
  totals: StatementTotals;
}

interface RawRow {
  date: Date;
  createdAt: Date;
  /** 0 = primary document (invoice / purchase order), 1 = payment. */
  kind: 0 | 1;
  type: StatementRowType;
  number: string;
  description: string;
  debit: number;
  credit: number;
}

const isoDay = (value: Date | undefined): string | null =>
  value ? value.toISOString().slice(0, 10) : null;

/** Chronological order, ties broken by creation time, documents before payments. */
function compareRawRows(a: RawRow, b: RawRow): number {
  const byDate = a.date.getTime() - b.date.getTime();
  if (byDate !== 0) return byDate;
  const byCreated = a.createdAt.getTime() - b.createdAt.getTime();
  if (byCreated !== 0) return byCreated;
  return a.kind - b.kind;
}

function buildRows(
  openingBalance: number,
  raw: RawRow[],
  delta: (row: RawRow) => number,
): { rows: StatementRow[]; totals: StatementTotals } {
  raw.sort(compareRawRows);
  let running = round2(openingBalance);
  let debitTotal = 0;
  let creditTotal = 0;

  const rows: StatementRow[] = raw.map((row) => {
    running = round2(running + delta(row));
    debitTotal = round2(debitTotal + row.debit);
    creditTotal = round2(creditTotal + row.credit);
    return {
      date: row.date.toISOString(),
      type: row.type,
      number: row.number,
      description: row.description,
      debit: row.debit,
      credit: row.credit,
      balance: running,
    };
  });

  return { rows, totals: { debit: debitTotal, credit: creditTotal, closingBalance: running } };
}

function paymentDescription(payment: { number: string; method: string; reference: string | null }): string {
  const parts = [`Payment ${payment.number}`, payment.method];
  if (payment.reference) parts.push(payment.reference);
  return parts.join(' · ');
}

/**
 * Builds a customer account statement. Invoices are debits (the customer owes
 * us), inbound payments are credits and outbound payments (refunds) are debits.
 */
export async function buildCustomerStatement(
  customerId: string,
  from?: Date,
  to?: Date,
): Promise<CustomerStatement> {
  const customer = await prisma.customer.findUnique({ where: { id: customerId } });
  if (!customer) throw ApiError.notFound('Customer not found');

  const range = from || to ? { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) } : undefined;

  const [invoices, payments] = await Promise.all([
    prisma.invoice.findMany({
      where: {
        customerId,
        status: { not: 'VOID' },
        ...(range ? { issueDate: range } : {}),
      },
      select: { id: true, number: true, total: true, issueDate: true, notes: true, createdAt: true },
    }),
    prisma.payment.findMany({
      where: { customerId, ...(range ? { paidAt: range } : {}) },
      select: {
        id: true,
        number: true,
        amount: true,
        direction: true,
        method: true,
        reference: true,
        paidAt: true,
        createdAt: true,
      },
    }),
  ]);

  let openingBalance = 0;
  if (from) {
    const [invoiceSum, inboundSum, outboundSum] = await Promise.all([
      prisma.invoice.aggregate({
        where: { customerId, status: { not: 'VOID' }, issueDate: { lt: from } },
        _sum: { total: true },
      }),
      prisma.payment.aggregate({
        where: { customerId, direction: 'INBOUND', paidAt: { lt: from } },
        _sum: { amount: true },
      }),
      prisma.payment.aggregate({
        where: { customerId, direction: 'OUTBOUND', paidAt: { lt: from } },
        _sum: { amount: true },
      }),
    ]);
    openingBalance = round2(
      Number(invoiceSum._sum.total ?? 0) -
        Number(inboundSum._sum.amount ?? 0) +
        Number(outboundSum._sum.amount ?? 0),
    );
  }

  const raw: RawRow[] = [];

  for (const invoice of invoices) {
    const note = invoice.notes?.trim();
    raw.push({
      date: invoice.issueDate,
      createdAt: invoice.createdAt,
      kind: 0,
      type: 'INVOICE',
      number: invoice.number,
      description: note && note.length > 0 ? note : `Invoice ${invoice.number}`,
      debit: round2(Number(invoice.total)),
      credit: 0,
    });
  }

  for (const payment of payments) {
    const inbound = payment.direction === 'INBOUND';
    const amount = round2(Number(payment.amount));
    raw.push({
      date: payment.paidAt,
      createdAt: payment.createdAt,
      kind: 1,
      type: 'PAYMENT',
      number: payment.number,
      description: paymentDescription(payment),
      debit: inbound ? 0 : amount,
      credit: inbound ? amount : 0,
    });
  }

  const { rows, totals } = buildRows(openingBalance, raw, (row) => row.debit - row.credit);

  return {
    customer: {
      id: customer.id,
      name: customer.name,
      email: customer.email,
      phone: customer.phone,
      address: customer.address,
      balance: Number(customer.balance),
      creditLimit: Number(customer.creditLimit),
    },
    from: isoDay(from),
    to: isoDay(to),
    openingBalance,
    rows,
    totals,
  };
}

/**
 * Builds a supplier account statement. Purchase orders are credits (we owe the
 * supplier), outbound payments are debits. A positive balance means we owe the
 * supplier.
 */
export async function buildSupplierStatement(
  supplierId: string,
  from?: Date,
  to?: Date,
): Promise<SupplierStatement> {
  const supplier = await prisma.supplier.findUnique({ where: { id: supplierId } });
  if (!supplier) throw ApiError.notFound('Supplier not found');

  const range = from || to ? { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) } : undefined;

  const [orders, payments] = await Promise.all([
    prisma.purchaseOrder.findMany({
      where: {
        supplierId,
        status: { not: 'CANCELLED' },
        ...(range ? { orderDate: range } : {}),
      },
      select: { id: true, number: true, total: true, orderDate: true, notes: true, createdAt: true },
    }),
    prisma.payment.findMany({
      where: { supplierId, direction: 'OUTBOUND', ...(range ? { paidAt: range } : {}) },
      select: {
        id: true,
        number: true,
        amount: true,
        method: true,
        reference: true,
        paidAt: true,
        createdAt: true,
      },
    }),
  ]);

  let openingBalance = 0;
  if (from) {
    const [orderSum, paymentSum] = await Promise.all([
      prisma.purchaseOrder.aggregate({
        where: { supplierId, status: { not: 'CANCELLED' }, orderDate: { lt: from } },
        _sum: { total: true },
      }),
      prisma.payment.aggregate({
        where: { supplierId, direction: 'OUTBOUND', paidAt: { lt: from } },
        _sum: { amount: true },
      }),
    ]);
    openingBalance = round2(Number(orderSum._sum.total ?? 0) - Number(paymentSum._sum.amount ?? 0));
  }

  const raw: RawRow[] = [];

  for (const order of orders) {
    const note = order.notes?.trim();
    raw.push({
      date: order.orderDate,
      createdAt: order.createdAt,
      kind: 0,
      type: 'PURCHASE_ORDER',
      number: order.number,
      description: note && note.length > 0 ? note : `Purchase order ${order.number}`,
      debit: 0,
      credit: round2(Number(order.total)),
    });
  }

  for (const payment of payments) {
    raw.push({
      date: payment.paidAt,
      createdAt: payment.createdAt,
      kind: 1,
      type: 'PAYMENT',
      number: payment.number,
      description: paymentDescription(payment),
      debit: round2(Number(payment.amount)),
      credit: 0,
    });
  }

  const { rows, totals } = buildRows(openingBalance, raw, (row) => row.credit - row.debit);

  return {
    supplier: {
      id: supplier.id,
      name: supplier.name,
      contact: supplier.contact,
      email: supplier.email,
      phone: supplier.phone,
      address: supplier.address,
      balance: Number(supplier.balance),
      paymentTermDays: supplier.paymentTermDays,
    },
    from: isoDay(from),
    to: isoDay(to),
    openingBalance,
    rows,
    totals,
  };
}
