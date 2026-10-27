import { Prisma } from '@prisma/client';
import { ApiError } from '../../lib/api-error';
import { localDayKey } from '../../lib/local-time';
import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import {
  customerAccessWhere,
  invoiceAccessWhere,
  salesOrderAccessWhere,
  type ScopeUser,
} from '../../lib/salesperson-scope';

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
  openingBalance?: number;
  periodBalance?: number;
}

export interface ReceivablesBySalespersonReport {
  from: string | null;
  to: string | null;
  rows: ReceivablesBySalespersonRow[];
  totals: {
    invoices: number;
    total: number;
    paid: number;
    balance: number;
    openingBalance: number;
    periodBalance: number;
  };
}

/** Outstanding customer balances attributed to the salesperson on the order. */
export async function buildReceivablesBySalesperson(
  fromInput?: Date,
  toInput?: Date,
  userId?: string,
): Promise<ReceivablesBySalespersonReport> {
  // The report is an as-of statement: invoices carried from before `from` must
  // stay visible (and are shown as the opening balance), so only the upper
  // bound is applied to the query.
  const dateWhere: Prisma.InvoiceWhereInput = {};
  if (toInput) dateWhere.issueDate = { lte: toInput };

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
      issueDate: true,
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

  const fromKey = fromInput ? startOfDayKey(fromInput) : null;
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
        openingBalance: 0,
        periodBalance: 0,
      } satisfies ReceivablesBySalespersonRow);
    const balance = Number(invoice.balance);
    row.invoices += 1;
    row.total = round2(row.total + Number(invoice.total));
    row.paid = round2(row.paid + Number(invoice.amountPaid));
    row.balance = round2(row.balance + balance);
    if (fromKey && startOfDayKey(invoice.issueDate) < fromKey) {
      row.openingBalance = round2((row.openingBalance ?? 0) + balance);
    } else {
      row.periodBalance = round2((row.periodBalance ?? 0) + balance);
    }
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
      openingBalance: round2(acc.openingBalance + (row.openingBalance ?? 0)),
      periodBalance: round2(acc.periodBalance + (row.periodBalance ?? 0)),
    }),
    { invoices: 0, total: 0, paid: 0, balance: 0, openingBalance: 0, periodBalance: 0 },
  );

  return {
    from: fromInput ? fromInput.toISOString() : null,
    to: toInput ? toInput.toISOString() : null,
    rows,
    totals,
  };
}

/** Local (browser) calendar-day key so period boundaries match the date picker. */
function startOfDayKey(date: Date): string {
  return localDayKey(date);
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
        cancelledAt: null,
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

export interface ItemMovementParty {
  type: 'CUSTOMER' | 'SUPPLIER' | 'CASH';
  name: string | null;
}

export interface ItemMovementRow {
  date: string;
  type: string;
  reference: string | null;
  /** Who the goods went to / came from, when the movement says so. */
  party: ItemMovementParty | null;
  note: string | null;
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
  product: {
    id: string;
    sku: string;
    name: string;
    category: string | null;
    unit: string;
    unitCost: number;
  };
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
    select: {
      id: true,
      sku: true,
      name: true,
      unit: true,
      costPrice: true,
      category: { select: { name: true } },
    },
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

  const references = [
    ...new Set(
      movements
        .map((movement) => movement.reference)
        .filter((value): value is string => Boolean(value)),
    ),
  ];
  const [salesOrders, purchaseOrders, returnOrders] = references.length
    ? await Promise.all([
        prisma.salesOrder.findMany({
          where: { number: { in: references } },
          select: {
            number: true,
            customer: { select: { name: true } },
            user: { select: { name: true } },
          },
        }),
        prisma.purchaseOrder.findMany({
          where: { number: { in: references } },
          select: { number: true, supplier: { select: { name: true } } },
        }),
        prisma.returnOrder.findMany({
          where: { number: { in: references } },
          select: {
            number: true,
            type: true,
            customer: { select: { name: true } },
            supplier: { select: { name: true } },
          },
        }),
      ])
    : [[], [], []];

  const salesByNumber = new Map(salesOrders.map((order) => [order.number, order]));
  const purchaseByNumber = new Map(purchaseOrders.map((order) => [order.number, order]));
  const returnByNumber = new Map(returnOrders.map((order) => [order.number, order]));

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
    const reference = movement.reference;
    let party: ItemMovementParty | null = null;
    if (reference) {
      if (movement.type === 'SALE') {
        const order = salesByNumber.get(reference);
        if (order) {
          party = order.customer
            ? { type: 'CUSTOMER', name: order.customer.name }
            : { type: 'CASH', name: order.user?.name ?? null };
        }
      } else if (movement.type === 'SALE_RETURN') {
        const order = returnByNumber.get(reference);
        if (order?.customer) {
          party = { type: 'CUSTOMER', name: order.customer.name };
        }
      } else if (movement.type === 'PURCHASE' || movement.type === 'RECEIVE') {
        const order = purchaseByNumber.get(reference);
        if (order?.supplier) {
          party = { type: 'SUPPLIER', name: order.supplier.name };
        }
      } else if (movement.type === 'PURCHASE_RETURN') {
        const order = returnByNumber.get(reference);
        if (order?.supplier) {
          party = { type: 'SUPPLIER', name: order.supplier.name };
        }
      }
    }

    return {
      date: movement.createdAt.toISOString(),
      type: movement.type,
      reference,
      party,
      note: movement.note,
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
      category: product.category?.name ?? null,
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

// ---------------------------------------------------------------------------
// Aging buckets (أعمار الديون والالتزامات)
// ---------------------------------------------------------------------------

export interface AgingRow {
  id: string;
  name: string;
  phone: string | null;
  invoices: number;
  current: number;
  d1_30: number;
  d31_60: number;
  d61_90: number;
  d90_plus: number;
  total: number;
  oldestDueDate: string | null;
}

export interface AgingReport {
  side: 'receivable' | 'payable';
  asOf: string;
  rows: AgingRow[];
  totals: {
    invoices: number;
    current: number;
    d1_30: number;
    d31_60: number;
    d61_90: number;
    d90_plus: number;
    total: number;
  };
}

const DAY_MS = 24 * 60 * 60 * 1000;

function emptyBuckets(): Pick<
  AgingRow,
  'current' | 'd1_30' | 'd31_60' | 'd61_90' | 'd90_plus' | 'total'
> {
  return { current: 0, d1_30: 0, d31_60: 0, d61_90: 0, d90_plus: 0, total: 0 };
}

/**
 * Outstanding balances split by how overdue they are.
 * Receivables age by invoice due date; payables (no due dates are recorded on
 * purchase orders) are reported as not yet due.
 */
export async function buildAgingReport(
  side: 'receivable' | 'payable',
  asOfInput?: Date,
  user?: ScopeUser,
): Promise<AgingReport> {
  const asOf = asOfInput ?? new Date();
  const map = new Map<string, AgingRow>();

  const rowFor = (id: string, name: string, phone: string | null): AgingRow => {
    const existing = map.get(id);
    if (existing) return existing;
    const row: AgingRow = { id, name, phone, invoices: 0, oldestDueDate: null, ...emptyBuckets() };
    map.set(id, row);
    return row;
  };

  const addToBucket = (row: AgingRow, daysOverdue: number, amount: number) => {
    if (daysOverdue <= 0) row.current = round2(row.current + amount);
    else if (daysOverdue <= 30) row.d1_30 = round2(row.d1_30 + amount);
    else if (daysOverdue <= 60) row.d31_60 = round2(row.d31_60 + amount);
    else if (daysOverdue <= 90) row.d61_90 = round2(row.d61_90 + amount);
    else row.d90_plus = round2(row.d90_plus + amount);
    row.total = round2(row.total + amount);
  };

  if (side === 'receivable') {
    const invoiceScope = user ? (invoiceAccessWhere(user) ?? {}) : {};
    const customerScope = user ? (customerAccessWhere(user) ?? {}) : {};
    const invoices = await prisma.invoice.findMany({
      where: { status: { in: ['ISSUED', 'PARTIALLY_PAID'] }, balance: { not: 0 }, ...invoiceScope },
      select: {
        number: true,
        dueDate: true,
        balance: true,
        customer: { select: { id: true, name: true, phone: true } },
      },
    });

    for (const invoice of invoices) {
      const customer = invoice.customer;
      const row = rowFor(customer?.id ?? 'walk-in', customer?.name ?? '—', customer?.phone ?? null);
      const dueDate = invoice.dueDate;
      const daysOverdue = dueDate ? Math.floor((asOf.getTime() - dueDate.getTime()) / DAY_MS) : 0;
      addToBucket(row, daysOverdue, Number(invoice.balance));
      row.invoices += 1;
      if (dueDate) {
        const iso = dueDate.toISOString();
        if (row.oldestDueDate == null || iso < row.oldestDueDate) row.oldestDueDate = iso;
      }
    }

    // Customers whose stored balance is not fully explained by their invoices
    // carry an opening balance (or an un-invoiced adjustment). Include that
    // remainder so customers created with an opening balance show up here too.
    const customers = await prisma.customer.findMany({
      where: { balance: { not: 0 }, ...customerScope },
      select: { id: true, name: true, phone: true, balance: true },
    });
    const invoicedByCustomer = await prisma.invoice.groupBy({
      by: ['customerId'],
      where: {
        status: { in: ['ISSUED', 'PARTIALLY_PAID'] },
        customerId: { not: null },
        ...invoiceScope,
      },
      _sum: { balance: true },
    });
    const invoicedMap = new Map<string, number>();
    for (const group of invoicedByCustomer) {
      if (group.customerId) invoicedMap.set(group.customerId, Number(group._sum.balance ?? 0));
    }
    for (const customer of customers) {
      const remainder = round2(
        Number(customer.balance) - (invoicedMap.get(customer.id) ?? 0),
      );
      if (remainder === 0) continue;
      const row = rowFor(customer.id, customer.name, customer.phone);
      // No due date is recorded for an opening balance: report it as not yet due.
      addToBucket(row, 0, remainder);
    }
  } else {
    // Supplier balances are not part of a representative's work.
    const suppliers =
      user && user.role === 'SALES'
        ? []
        : await prisma.supplier.findMany({
            where: { balance: { not: 0 } },
            select: { id: true, name: true, phone: true, balance: true },
          });
    for (const supplier of suppliers) {
      const row = rowFor(supplier.id, supplier.name, supplier.phone);
      addToBucket(row, 0, Number(supplier.balance));
    }
  }

  const rows = [...map.values()]
    .filter((row) => row.total !== 0)
    .sort((a, b) => b.total - a.total || a.name.localeCompare(b.name));

  const totals = rows.reduce(
    (acc, row) => ({
      invoices: acc.invoices + row.invoices,
      current: round2(acc.current + row.current),
      d1_30: round2(acc.d1_30 + row.d1_30),
      d31_60: round2(acc.d31_60 + row.d31_60),
      d61_90: round2(acc.d61_90 + row.d61_90),
      d90_plus: round2(acc.d90_plus + row.d90_plus),
      total: round2(acc.total + row.total),
    }),
    { invoices: 0, current: 0, d1_30: 0, d31_60: 0, d61_90: 0, d90_plus: 0, total: 0 },
  );

  return { side, asOf: asOf.toISOString(), rows, totals };
}

// ---------------------------------------------------------------------------
// Sales shortages / what needs purchasing (نواقص طلبيات العملاء)
// ---------------------------------------------------------------------------

export interface ShortageOrderRef {
  orderId: string;
  orderNumber: string;
  customer: string | null;
  orderDate: string;
  /** What this order still needs of the product. */
  outstanding: number;
}

export interface ShortageRow {
  productId: string;
  sku: string;
  name: string;
  category: string | null;
  unit: string;
  /** Units on hand across all warehouses (respecting reserved). */
  onHand: number;
  /** Units still to be delivered across every open sales order. */
  required: number;
  /** Units that must be bought/received to satisfy the open orders. */
  shortage: number;
  unitCost: number;
  /** Rough purchase value (shortage × cost). */
  purchaseValue: number;
  /** Orders waiting on this product. */
  orders: ShortageOrderRef[];
}

export interface ShortagesReport {
  generatedAt: string;
  rows: ShortageRow[];
  totals: {
    products: number;
    required: number;
    onHand: number;
    shortage: number;
    purchaseValue: number;
  };
}

/**
 * Lists the products that open sales orders still need but that are not (fully)
 * on hand, so the shop knows exactly what to purchase to keep going.
 *
 * "Open" orders are any that are not cancelled and not fully fulfilled. For
 * each line we look at what is still to be delivered (`quantity - fulfilledQty`)
 * and compare it against the physical stock on hand.
 */
export async function buildShortagesReport(
  warehouseId?: string,
  user?: ScopeUser,
): Promise<ShortagesReport> {
  const access = user ? salesOrderAccessWhere(user) : null;
  const lines = await prisma.salesOrderLine.findMany({
    where: {
      salesOrder: {
        status: { in: ['DRAFT', 'CONFIRMED', 'PARTIALLY_FULFILLED'] },
        ...(warehouseId ? { warehouseId } : {}),
        ...(access ?? {}),
      },
    },
    select: {
      productId: true,
      quantity: true,
      fulfilledQty: true,
      salesOrder: {
        select: {
          id: true,
          number: true,
          orderDate: true,
          customer: { select: { name: true } },
        },
      },
      product: {
        select: {
          sku: true,
          name: true,
          unit: true,
          costPrice: true,
          deletedAt: true,
          category: { select: { name: true } },
        },
      },
    },
  });

  const levels = await prisma.stockLevel.findMany({
    where: warehouseId ? { warehouseId } : {},
    select: { productId: true, quantity: true, reserved: true },
  });
  const onHandById = new Map<string, number>();
  for (const level of levels) {
    const available = level.quantity - level.reserved;
    onHandById.set(level.productId, round2((onHandById.get(level.productId) ?? 0) + available));
  }

  const map = new Map<string, ShortageRow>();
  for (const line of lines) {
    const outstanding = line.quantity - line.fulfilledQty;
    if (outstanding <= 0) continue;

    const row =
      map.get(line.productId) ??
      ({
        productId: line.productId,
        sku: line.product.sku,
        name: line.product.name,
        category: line.product.category?.name ?? null,
        unit: line.product.unit,
        onHand: onHandById.get(line.productId) ?? 0,
        required: 0,
        shortage: 0,
        unitCost: Number(line.product.costPrice),
        purchaseValue: 0,
        orders: [],
      } satisfies ShortageRow);

    row.required = round2(row.required + outstanding);
    row.orders.push({
      orderId: line.salesOrder.id,
      orderNumber: line.salesOrder.number,
      customer: line.salesOrder.customer?.name ?? null,
      orderDate: line.salesOrder.orderDate.toISOString(),
      outstanding,
    });
    map.set(line.productId, row);
  }

  const rows = [...map.values()];
  for (const row of rows) {
    row.shortage = round2(Math.max(0, row.required - row.onHand));
    row.purchaseValue = round2(row.shortage * row.unitCost);
    row.orders.sort((a, b) => a.orderDate.localeCompare(b.orderDate));
  }

  // Only surface products that are actually short; fully-covered products are
  // still returned with `shortage: 0` only when nothing at all is missing.
  const shortRows = rows
    .filter((row) => row.shortage > 0)
    .sort((a, b) => b.purchaseValue - a.purchaseValue || a.name.localeCompare(b.name));

  const totals = shortRows.reduce(
    (acc, row) => ({
      products: acc.products + 1,
      required: round2(acc.required + row.required),
      onHand: round2(acc.onHand + row.onHand),
      shortage: round2(acc.shortage + row.shortage),
      purchaseValue: round2(acc.purchaseValue + row.purchaseValue),
    }),
    { products: 0, required: 0, onHand: 0, shortage: 0, purchaseValue: 0 },
  );

  return {
    generatedAt: new Date().toISOString(),
    rows: shortRows,
    totals,
  };
}

// ---------------------------------------------------------------------------
// Sales-order fulfilment board (البضاعة المتاحة والمطلوبة لكل طلبية عميل)
// ---------------------------------------------------------------------------

export interface OrderFulfilmentLine {
  lineId: string;
  productId: string;
  sku: string;
  name: string;
  unit: string;
  /** Units the customer ordered on this line. */
  ordered: number;
  /** Units already delivered. */
  fulfilled: number;
  /** Units still to be delivered (`ordered - fulfilled`). */
  required: number;
  /** Units physically on hand for the order's warehouse. */
  available: number;
  /** Units that must be purchased to cover the outstanding request. */
  shortage: number;
}

export interface OrderFulfilmentRow {
  orderId: string;
  orderNumber: string;
  customer: string | null;
  orderDate: string;
  status: string;
  warehouse: string;
  /** True when every outstanding line can be met from stock. */
  fullyAvailable: boolean;
  lines: OrderFulfilmentLine[];
  totals: { required: number; available: number; shortage: number };
}

export interface OrderFulfilmentReport {
  generatedAt: string;
  rows: OrderFulfilmentRow[];
  totals: {
    orders: number;
    lines: number;
    required: number;
    available: number;
    shortage: number;
  };
}

/**
 * One row per open sales order showing, line by line, what is available on hand
 * (`available`), what the customer ordered (`required`) and what still has to be
 * purchased (`shortage`). This is the "goods available vs. goods to buy" board
 * for finishing the order.
 */
export async function buildOrderFulfilmentReport(
  warehouseId?: string,
  user?: ScopeUser,
): Promise<OrderFulfilmentReport> {
  const access = user ? salesOrderAccessWhere(user) : null;
  const orders = await prisma.salesOrder.findMany({
    where: {
      status: { in: ['DRAFT', 'CONFIRMED', 'PARTIALLY_FULFILLED'] },
      ...(warehouseId ? { warehouseId } : {}),
      ...(access ?? {}),
    },
    orderBy: { orderDate: 'asc' },
    include: {
      customer: { select: { name: true } },
      warehouse: { select: { code: true, name: true } },
      lines: {
        orderBy: { id: 'asc' },
        include: {
          product: { select: { sku: true, name: true, unit: true } },
        },
      },
    },
  });

  const levels = await prisma.stockLevel.findMany({
    where: warehouseId ? { warehouseId } : {},
    select: { productId: true, warehouseId: true, quantity: true, reserved: true },
  });
  const onHand = new Map<string, number>();
  for (const level of levels) {
    const key = `${level.warehouseId}:${level.productId}`;
    const available = Number(level.quantity) - Number(level.reserved);
    onHand.set(key, round2((onHand.get(key) ?? 0) + available));
  }

  const rows: OrderFulfilmentRow[] = [];
  for (const order of orders) {
    const lines: OrderFulfilmentLine[] = [];
    for (const line of order.lines) {
      const required = line.quantity - line.fulfilledQty;
      if (required <= 0) continue;
      const available = onHand.get(`${order.warehouseId}:${line.productId}`) ?? 0;
      lines.push({
        lineId: line.id,
        productId: line.productId,
        sku: line.product.sku,
        name: line.product.name,
        unit: line.product.unit,
        ordered: line.quantity,
        fulfilled: line.fulfilledQty,
        required,
        available,
        shortage: round2(Math.max(0, required - available)),
      });
    }
    if (lines.length === 0) continue;

    const totals = lines.reduce(
      (acc, line) => ({
        required: round2(acc.required + line.required),
        available: round2(acc.available + line.available),
        shortage: round2(acc.shortage + line.shortage),
      }),
      { required: 0, available: 0, shortage: 0 },
    );

    rows.push({
      orderId: order.id,
      orderNumber: order.number,
      customer: order.customer?.name ?? null,
      orderDate: order.orderDate.toISOString(),
      status: order.status,
      warehouse: order.warehouse.name,
      fullyAvailable: totals.shortage === 0,
      lines,
      totals,
    });
  }

  // Short orders first so the shop sees what is blocking sales immediately.
  rows.sort((a, b) => Number(a.fullyAvailable) - Number(b.fullyAvailable));

  const totals = rows.reduce(
    (acc, row) => ({
      orders: acc.orders + 1,
      lines: acc.lines + row.lines.length,
      required: round2(acc.required + row.totals.required),
      available: round2(acc.available + row.totals.available),
      shortage: round2(acc.shortage + row.totals.shortage),
    }),
    { orders: 0, lines: 0, required: 0, available: 0, shortage: 0 },
  );

  return { generatedAt: new Date().toISOString(), rows, totals };
}
