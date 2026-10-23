import { Router, type Request } from 'express';
import { Prisma } from '@prisma/client';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, ok } from '../../lib/http';
import { round2 } from '../../lib/money';
import { prisma } from '../../lib/prisma';
import { asDate, asString } from '../../lib/query';
import {
  assertCustomerAccess,
  canViewProfit,
  customerAccessWhere,
  invoiceAccessWhere,
  isSalesperson,
  salesOrderAccessWhere,
  scopedSalespersonId,
} from '../../lib/salesperson-scope';
import { authenticateToken } from '../../middleware/authenticate-token';
import { currentUser } from '../../middleware/authenticate';
import { requirePermission, requireAdmin } from '../../middleware/authorize';
import { lowStockProducts } from '../inventory/inventory.service';
import { postJournal } from '../accounting/accounting.service';
import {
  buildInventoryValuation,
  buildProfitReport,
  buildPurchasesReport,
  buildSalesReport,
  buildTaxReport,
  buildTopProducts,
  dayKey,
} from './reports.service';
import { buildCustomerStatement, buildSupplierStatement } from './statement.service';
import { buildBackupWorkbook } from './backup.service';
import {
  buildAgingReport,
  buildItemMovement,
  buildOrderFulfilmentReport,
  buildReceivablesBySalesperson,
  buildShortagesReport,
  buildStockBalance,
  buildSupplierPayables,
} from './analytics.service';
import {
  buildCashFlowReport,
  buildDeadStockReport,
  buildPaymentsByMethod,
  buildPurchasesBySupplier,
  buildReturnsReport,
  buildSalesByCategory,
  buildSalesByCustomer,
  buildSalesBySalesperson,
} from './reports.extra.service';
import {
  buildCollectionsBySalesperson,
  buildConsolidatedSalesNote,
  buildProfitBySalesperson,
  buildSalespersonCustomerDebt,
  buildSalespersonStatement,
} from './salespeople.service';

const router = Router();
// Accepts the bearer header for JSON calls and `?token=` for links opened in a
// browser (e.g. the Excel backup download).
router.use(authenticateToken);

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

// GET /reports/dashboard
function requireProfitAccess(req: Request): void {
  if (!canViewProfit(currentUser(req))) {
    throw ApiError.forbidden('Only managers and administrators can view profit');
  }
}

/** A representative may only open their own salesperson statements. */
function requireOwnSalesperson(req: Request): void {
  const user = currentUser(req);
  if (isSalesperson(user) && req.params.id !== user.id) {
    throw ApiError.forbidden('You can only view your own reports', 'SALESPERSON_NOT_ASSIGNED');
  }
}

/** Removes cost and profit figures from a report for users who may not see profit. */
function stripProfit<T extends { totals?: object; rows?: object[] }>(
  report: T,
  keys: string[],
): T {
  const strip = (row: object) => {
    const copy = { ...row } as Record<string, unknown>;
    for (const key of keys) delete copy[key];
    return copy;
  };
  return {
    ...report,
    totals: report.totals ? strip(report.totals) : report.totals,
    rows: report.rows?.map(strip),
  } as T;
}

router.get(
  '/dashboard',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    const own = isSalesperson(user);
    const orderScope = salesOrderAccessWhere(user) ?? {};
    const invoiceScope = invoiceAccessWhere(user) ?? {};
    const now = new Date();
    const todayStart = startOfDay(now);
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const last30 = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const weekStart = new Date(todayStart.getTime() - 6 * 24 * 60 * 60 * 1000);

    const [
      productCount,
      customerCount,
      supplierCount,
      warehouseCount,
      salesToday,
      salesMonth,
      receivables,
      payables,
      levels,
      lowStock,
      recentMovements,
      salesLines,
      recentOrders,
    ] = await Promise.all([
      prisma.product.count({ where: { deletedAt: null, active: true } }),
      prisma.customer.count({ where: { active: true, ...(customerAccessWhere(user) ?? {}) } }),
      // Supplier figures are not part of a representative's work.
      own ? 0 : prisma.supplier.count({ where: { active: true } }),
      prisma.warehouse.count({ where: { active: true } }),
      prisma.salesOrder.aggregate({
        where: { orderDate: { gte: todayStart }, status: { not: 'CANCELLED' }, ...orderScope },
        _sum: { total: true },
        _count: { _all: true },
      }),
      prisma.salesOrder.aggregate({
        where: { orderDate: { gte: monthStart }, status: { not: 'CANCELLED' }, ...orderScope },
        _sum: { total: true },
        _count: { _all: true },
      }),
      prisma.invoice.aggregate({
        where: { status: { in: ['ISSUED', 'PARTIALLY_PAID'] }, ...invoiceScope },
        _sum: { balance: true },
      }),
      own
        ? { _sum: { balance: 0 } }
        : prisma.supplier.aggregate({ _sum: { balance: true } }),
      prisma.stockLevel.findMany({ select: { productId: true, quantity: true } }),
      lowStockProducts(),
      prisma.stockMovement.findMany({
        take: 10,
        orderBy: { createdAt: 'desc' },
        include: {
          product: { select: { id: true, sku: true, name: true } },
          location: { select: { id: true, code: true, name: true } },
        },
      }),
      prisma.salesOrderLine.findMany({
        where: {
          salesOrder: { orderDate: { gte: last30 }, status: { not: 'CANCELLED' }, ...orderScope },
        },
        select: { productId: true, quantity: true, unitPrice: true },
      }),
      prisma.salesOrder.findMany({
        where: { orderDate: { gte: weekStart }, status: { not: 'CANCELLED' }, ...orderScope },
        select: { orderDate: true, total: true },
      }),
    ]);

    const productIds = [...new Set(levels.map((level) => level.productId))];
    const products = productIds.length
      ? await prisma.product.findMany({
          where: { id: { in: productIds } },
          select: { id: true, costPrice: true, salePrice: true },
        })
      : [];
    const priceById = new Map(
      products.map((product) => [
        product.id,
        { cost: Number(product.costPrice), sale: Number(product.salePrice) },
      ]),
    );

    let stockUnits = 0;
    let stockCostValue = 0;
    let stockRetailValue = 0;
    for (const level of levels) {
      const prices = priceById.get(level.productId);
      stockUnits += level.quantity;
      stockCostValue += level.quantity * (prices?.cost ?? 0);
      stockRetailValue += level.quantity * (prices?.sale ?? 0);
    }

    const topMap = new Map<string, { quantity: number; revenue: number }>();
    for (const line of salesLines) {
      const entry = topMap.get(line.productId) ?? { quantity: 0, revenue: 0 };
      entry.quantity += line.quantity;
      entry.revenue += line.quantity * Number(line.unitPrice);
      topMap.set(line.productId, entry);
    }
    const topIds = [...topMap.entries()].sort((a, b) => b[1].revenue - a[1].revenue).slice(0, 5);
    const topProducts = topIds.length
      ? await prisma.product.findMany({
          where: { id: { in: topIds.map(([id]) => id) } },
          select: { id: true, sku: true, name: true },
        })
      : [];
    const topNameById = new Map(topProducts.map((product) => [product.id, product]));

    const series: { date: string; total: number; orders: number }[] = [];
    for (let i = 6; i >= 0; i -= 1) {
      const day = new Date(todayStart.getTime() - i * 24 * 60 * 60 * 1000);
      series.push({ date: dayKey(day), total: 0, orders: 0 });
    }
    const seriesByDate = new Map(series.map((point) => [point.date, point]));
    for (const order of recentOrders) {
      const point = seriesByDate.get(dayKey(order.orderDate));
      if (point) {
        point.total = round2(point.total + Number(order.total));
        point.orders += 1;
      }
    }

    ok(res, {
      counts: {
        products: productCount,
        customers: customerCount,
        suppliers: supplierCount,
        warehouses: warehouseCount,
        lowStock: lowStock.length,
      },
      inventory: {
        units: stockUnits,
        costValue: round2(stockCostValue),
        retailValue: round2(stockRetailValue),
      },
      sales: {
        today: round2(Number(salesToday._sum.total ?? 0)),
        todayOrders: salesToday._count._all,
        month: round2(Number(salesMonth._sum.total ?? 0)),
        monthOrders: salesMonth._count._all,
      },
      receivables: round2(Number(receivables._sum.balance ?? 0)),
      payables: round2(Number(payables._sum.balance ?? 0)),
      lowStock: lowStock.slice(0, 10).map((row) => ({
        id: row.product.id,
        sku: row.product.sku,
        name: row.product.name,
        quantity: row.quantity,
        reorderLevel: row.product.reorderLevel,
        shortage: row.shortage,
      })),
      topProducts: topIds.map(([productId, stats]) => ({
        productId,
        sku: topNameById.get(productId)?.sku ?? '',
        name: topNameById.get(productId)?.name ?? '',
        quantitySold: stats.quantity,
        revenue: round2(stats.revenue),
      })),
      salesSeries: series,
      recentMovements: recentMovements.map((movement) => ({
        ...movement,
        unitCost: Number(movement.unitCost),
      })),
    });
  }),
);

// GET /reports/sales
router.get(
  '/sales',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const groupBy = asString(req.query.groupBy) === 'month' ? 'month' : 'day';

    ok(res, await buildSalesReport(from, to, groupBy, currentUser(req)));
  }),
);

// GET /reports/inventory-valuation
router.get(
  '/inventory-valuation',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const warehouseId = asString(req.query.warehouseId);
    ok(res, await buildInventoryValuation(warehouseId));
  }),
);

// GET /reports/top-products
router.get(
  '/top-products',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const limit = Number(asString(req.query.limit) ?? 10);

    ok(res, await buildTopProducts(from, to, limit, currentUser(req)));
  }),
);

// GET /reports/customer-balances
router.get(
  '/customer-balances',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    const salespersonId = scopedSalespersonId(user, asString(req.query.salespersonId));
    const customers = await prisma.customer.findMany({
      where: {
        balance: { not: 0 },
        ...(customerAccessWhere(user) ?? {}),
        ...(salespersonId ? { salespersonId } : {}),
      },
      orderBy: { balance: 'desc' },
      include: {
        salesperson: { select: { name: true } },
        _count: { select: { invoices: true } },
      },
    });
    ok(
      res,
      customers.map((customer) => ({
        id: customer.id,
        name: customer.name,
        email: customer.email,
        phone: customer.phone,
        creditLimit: Number(customer.creditLimit),
        balance: Number(customer.balance),
        invoices: customer._count.invoices,
        salesperson: customer.salesperson?.name ?? null,
      })),
    );
  }),
);

// GET /reports/dormant-customers?days=90&salespersonId=
router.get(
  '/dormant-customers',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const user = currentUser(req);
    const salespersonId = scopedSalespersonId(user, asString(req.query.salespersonId));
    const days = Math.max(1, Number(asString(req.query.days) ?? 90));
    const customers = await prisma.customer.findMany({
      where: {
        active: true,
        ...(customerAccessWhere(user) ?? {}),
        ...(salespersonId ? { salespersonId } : {}),
      },
      select: {
        id: true,
        name: true,
        phone: true,
        balance: true,
        salesperson: { select: { name: true } },
      },
    });
    const lastInvoices = await prisma.invoice.groupBy({
      by: ['customerId'],
      where: {
        customerId: { in: customers.map((customer) => customer.id) },
        status: { not: 'VOID' },
      },
      _max: { issueDate: true },
    });
    const lastByCustomer = new Map(
      lastInvoices.map((row) => [row.customerId, row._max.issueDate]),
    );
    const rows = customers
      .map((customer) => {
        const last = lastByCustomer.get(customer.id) ?? null;
        const daysSince = last
          ? Math.floor((Date.now() - last.getTime()) / (24 * 60 * 60 * 1000))
          : null;
        return {
          id: customer.id,
          name: customer.name,
          phone: customer.phone,
          salesperson: customer.salesperson?.name ?? null,
          lastInvoiceAt: last ? last.toISOString() : null,
          daysSince,
          balance: Number(customer.balance),
        };
      })
      .filter((row) => row.lastInvoiceAt === null || (row.daysSince ?? 0) >= days)
      .sort((a, b) => (b.daysSince ?? 99999) - (a.daysSince ?? 99999));
    ok(res, { days, rows, totals: { customers: rows.length } });
  }),
);

// GET /reports/price-list?availableOnly=true&categoryId=
router.get(
  '/price-list',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const availableOnly = asString(req.query.availableOnly) === 'true';
    const categoryId = asString(req.query.categoryId);
    const products = await prisma.product.findMany({
      where: {
        active: true,
        deletedAt: null,
        ...(categoryId ? { categoryId } : {}),
      },
      orderBy: [{ name: 'asc' }],
      select: {
        id: true,
        sku: true,
        name: true,
        unit: true,
        salePrice: true,
        boxPrice: true,
        cartonPrice: true,
        boxesPerCarton: true,
        category: { select: { name: true } },
      },
    });
    const stock = await prisma.stockLevel.groupBy({
      by: ['productId'],
      _sum: { quantity: true },
    });
    const stockById = new Map(
      stock.map((row) => [row.productId, Number(row._sum.quantity ?? 0)]),
    );
    const rows = products
      .map((product) => ({
        id: product.id,
        sku: product.sku,
        name: product.name,
        unit: product.unit,
        category: product.category?.name ?? null,
        salePrice: Number(product.salePrice),
        boxPrice: product.boxPrice == null ? null : Number(product.boxPrice),
        cartonPrice:
          product.cartonPrice == null ? null : Number(product.cartonPrice),
        boxesPerCarton: product.boxesPerCarton,
        quantity: stockById.get(product.id) ?? 0,
      }))
      .filter((row) => !availableOnly || row.quantity > 0);
    ok(res, { rows, totals: { products: rows.length } });
  }),
);

// GET /reports/investment-equation
router.get(
  '/investment-equation',
  requirePermission('reports.read'),
  asyncHandler(async (_req, res) => {
    const [stock, products, boxes, paymentGroups, transfersOut, transfersIn, expenseGroups, customers, suppliers] =
      await Promise.all([
        prisma.stockLevel.groupBy({
          by: ['productId'],
          _sum: { quantity: true },
        }),
        prisma.product.findMany({
          select: { id: true, name: true, sku: true, costPrice: true },
        }),
        prisma.cashBox.findMany({
          where: { active: true },
          select: { id: true, name: true, openingBalance: true },
        }),
        prisma.payment.groupBy({
          by: ['cashBoxId', 'direction'],
          where: { cashBoxId: { not: null }, cancelledAt: null },
          _sum: { amount: true },
        }),
        prisma.cashTransfer.groupBy({
          by: ['fromBoxId'],
          where: { cancelledAt: null },
          _sum: { amount: true },
        }),
        prisma.cashTransfer.groupBy({
          by: ['toBoxId'],
          where: { cancelledAt: null },
          _sum: { amount: true },
        }),
        prisma.expense.groupBy({
          by: ['cashBoxId'],
          where: { cashBoxId: { not: null }, cancelledAt: null },
          _sum: { amount: true },
        }),
        prisma.customer.findMany({
          select: { id: true, name: true, balance: true },
          orderBy: { balance: 'desc' },
        }),
        prisma.supplier.findMany({
          select: { id: true, name: true, balance: true },
          orderBy: { balance: 'desc' },
        }),
      ]);

    const productById = new Map(products.map((product) => [product.id, product]));
    const inventory = stock
      .map((level) => {
        const product = productById.get(level.productId);
        const quantity = Number(level._sum.quantity ?? 0);
        return {
          id: level.productId,
          name: product?.name ?? level.productId,
          sku: product?.sku ?? null,
          quantity,
          value: round2(quantity * Number(product?.costPrice ?? 0)),
        };
      })
      .filter((row) => row.quantity !== 0);

    const paymentIn = new Map<string, number>();
    const paymentOut = new Map<string, number>();
    for (const group of paymentGroups) {
      if (!group.cashBoxId) continue;
      const target = group.direction === 'INBOUND' ? paymentIn : paymentOut;
      target.set(group.cashBoxId, round2(Number(group._sum.amount ?? 0)));
    }
    const transferOut = new Map(
      transfersOut.map((row) => [row.fromBoxId, round2(Number(row._sum.amount ?? 0))]),
    );
    const transferIn = new Map(
      transfersIn.map((row) => [row.toBoxId, round2(Number(row._sum.amount ?? 0))]),
    );
    const expensesByBox = new Map(
      expenseGroups.map((row) => [row.cashBoxId!, round2(Number(row._sum.amount ?? 0))]),
    );
    const cash = boxes
      .map((box) => ({
        id: box.id,
        name: box.name,
        balance: round2(
          Number(box.openingBalance) +
            (paymentIn.get(box.id) ?? 0) -
            (paymentOut.get(box.id) ?? 0) +
            (transferIn.get(box.id) ?? 0) -
            (transferOut.get(box.id) ?? 0) -
            (expensesByBox.get(box.id) ?? 0),
        ),
      }))
      .filter((row) => row.balance !== 0);

    const customerRows = customers
      .map((customer) => ({
        id: customer.id,
        name: customer.name,
        balance: round2(Number(customer.balance)),
      }))
      .filter((row) => row.balance !== 0);
    const supplierRows = suppliers
      .map((supplier) => ({
        id: supplier.id,
        name: supplier.name,
        balance: round2(Number(supplier.balance)),
      }))
      .filter((row) => row.balance !== 0);

    const inventoryTotal = round2(inventory.reduce((sum, row) => sum + row.value, 0));
    const cashTotal = round2(cash.reduce((sum, row) => sum + row.balance, 0));
    const customersTotal = round2(
      customerRows.reduce((sum, row) => sum + row.balance, 0),
    );
    const suppliersTotal = round2(
      supplierRows.reduce((sum, row) => sum + row.balance, 0),
    );

    ok(res, {
      inventory: { total: inventoryTotal, rows: inventory },
      cash: { total: cashTotal, rows: cash },
      customers: { total: customersTotal, rows: customerRows },
      suppliers: { total: suppliersTotal, rows: supplierRows },
      net: round2(inventoryTotal + cashTotal + customersTotal - suppliersTotal),
    });
  }),
);

// POST /reports/reconcile-inventory?apply=true — compares physical stock value
// with the Inventory ledger account and can post the difference as opening
// equity. Preview by default.
router.post(
  '/reconcile-inventory',
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const apply = asString(req.query.apply) === 'true';
    const [levels, products, inventoryAccount] = await Promise.all([
      prisma.stockLevel.groupBy({ by: ['productId'], _sum: { quantity: true } }),
      prisma.product.findMany({ select: { id: true, costPrice: true } }),
      prisma.account.findUnique({ where: { code: '1200' } }),
    ]);
    const costById = new Map(
      products.map((product) => [product.id, Number(product.costPrice)]),
    );
    const stockValue = round2(
      levels.reduce(
        (sum, level) =>
          sum +
          Number(level._sum.quantity ?? 0) *
            (costById.get(level.productId) ?? 0),
        0,
      ),
    );
    const ledger = inventoryAccount
      ? await prisma.journalLine.aggregate({
          where: { accountId: inventoryAccount.id },
          _sum: { debit: true, credit: true },
        })
      : null;
    const ledgerValue = round2(
      Number(ledger?._sum.debit ?? 0) - Number(ledger?._sum.credit ?? 0),
    );
    const difference = round2(stockValue - ledgerValue);

    if (apply && difference !== 0) {
      await prisma.$transaction(async (tx) => {
        await postJournal(tx, {
          memo: 'Inventory reconciliation with physical stock',
          sourceType: 'INVENTORY_RECONCILIATION',
          lines:
            difference > 0
              ? [
                  {
                    accountCode: '1200',
                    debit: difference,
                    description: 'Inventory reconciliation',
                  },
                  {
                    accountCode: '3000',
                    credit: difference,
                    description: 'Opening equity for inventory',
                  },
                ]
              : [
                  {
                    accountCode: '3000',
                    debit: -difference,
                    description: 'Opening equity for inventory',
                  },
                  {
                    accountCode: '1200',
                    credit: -difference,
                    description: 'Inventory reconciliation',
                  },
                ],
          userId: currentUser(req).id,
        });
      });
    }

    ok(res, { stockValue, ledgerValue, difference, applied: apply });
  }),
);

// GET /reports/supplier-balances
router.get(
  '/supplier-balances',
  requirePermission('reports.read'),
  asyncHandler(async (_req, res) => {
    const suppliers = await prisma.supplier.findMany({
      where: { balance: { not: 0 } },
      orderBy: { balance: 'desc' },
      include: { _count: { select: { purchaseOrders: true } } },
    });
    ok(
      res,
      suppliers.map((supplier) => ({
        id: supplier.id,
        name: supplier.name,
        email: supplier.email,
        phone: supplier.phone,
        balance: Number(supplier.balance),
        purchaseOrders: supplier._count.purchaseOrders,
      })),
    );
  }),
);

// GET /reports/receivables-by-salesperson
router.get(
  '/receivables-by-salesperson',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const userId = scopedSalespersonId(currentUser(req), asString(req.query.userId));
    ok(res, await buildReceivablesBySalesperson(from, to, userId));
  }),
);

// GET /reports/supplier-payables
router.get(
  '/supplier-payables',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    ok(res, await buildSupplierPayables(from, to));
  }),
);

// GET /reports/consolidated-sales-note
router.get(
  '/consolidated-sales-note',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const rawTo = asDate(req.query.to);
    // A date-only `to` means the whole day, not midnight.
    const to = rawTo
      ? new Date(rawTo.getFullYear(), rawTo.getMonth(), rawTo.getDate(), 23, 59, 59, 999)
      : undefined;
    const salespersonId = scopedSalespersonId(currentUser(req), asString(req.query.salespersonId));
    ok(res, await buildConsolidatedSalesNote(from, to, salespersonId));
  }),
);

// GET /reports/profit-by-salesperson
router.get(
  '/profit-by-salesperson',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    requireProfitAccess(req);
    const salespersonId = scopedSalespersonId(currentUser(req), asString(req.query.salespersonId));
    ok(res, await buildProfitBySalesperson(from, to, salespersonId));
  }),
);

// GET /reports/collections-by-salesperson
router.get(
  '/collections-by-salesperson',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const salespersonId = scopedSalespersonId(currentUser(req), asString(req.query.salespersonId));
    ok(res, await buildCollectionsBySalesperson(from, to, salespersonId));
  }),
);

// GET /reports/salespeople/:id/statement
router.get(
  '/salespeople/:id/statement',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    requireOwnSalesperson(req);
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    try {
      ok(res, await buildSalespersonStatement(req.params.id, from, to));
    } catch (error) {
      if (error instanceof Error && error.message === 'SALESPERSON_NOT_FOUND') {
        throw ApiError.notFound('Salesperson not found', 'SALESPERSON_NOT_FOUND');
      }
      throw error;
    }
  }),
);

// GET /reports/salespeople/:id/customers — per-customer debt ledger
router.get(
  '/salespeople/:id/customers',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    requireOwnSalesperson(req);
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const rawFilter = asString(req.query.filter);
    const filter =
      rawFilter === 'debtors' || rawFilter === 'creditors' ? rawFilter : 'all';
    try {
      ok(res, await buildSalespersonCustomerDebt(req.params.id, from, to, filter));
    } catch (error) {
      if (error instanceof Error && error.message === 'SALESPERSON_NOT_FOUND') {
        throw ApiError.notFound('Salesperson not found', 'SALESPERSON_NOT_FOUND');
      }
      throw error;
    }
  }),
);

// GET /reports/stock-balance
router.get(
  '/stock-balance',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const warehouseId = asString(req.query.warehouseId);
    const categoryId = asString(req.query.categoryId);
    ok(res, await buildStockBalance(warehouseId, categoryId));
  }),
);

// GET /reports/item-movement
router.get(
  '/item-movement',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const productId = asString(req.query.productId);
    if (!productId) throw ApiError.badRequest('productId is required', 'PRODUCT_REQUIRED');
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const warehouseId = asString(req.query.warehouseId);
    ok(res, await buildItemMovement(productId, from, to, warehouseId));
  }),
);

// GET /reports/customers/:id/statement
router.get(
  '/customers/:id/statement',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    await assertCustomerAccess(currentUser(req), req.params.id);
    ok(res, await buildCustomerStatement(req.params.id, from, to));
  }),
);

// GET /reports/suppliers/:id/statement
router.get(
  '/suppliers/:id/statement',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    ok(res, await buildSupplierStatement(req.params.id, from, to));
  }),
);

// GET /reports/purchases
router.get(
  '/purchases',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const groupBy = asString(req.query.groupBy) === 'month' ? 'month' : 'day';
    ok(res, await buildPurchasesReport(from, to, groupBy));
  }),
);

// GET /reports/profit
router.get(
  '/profit',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    requireProfitAccess(req);
    ok(res, await buildProfitReport(from, to));
  }),
);

// GET /reports/tax
router.get(
  '/tax',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    ok(res, await buildTaxReport(from, to));
  }),
);

// GET /reports/aging?side=receivable|payable
router.get(
  '/aging',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const side = asString(req.query.side) === 'payable' ? 'payable' : 'receivable';
    const asOf = asDate(req.query.asOf);
    ok(res, await buildAgingReport(side, asOf, currentUser(req)));
  }),
);

// GET /reports/shortages — what open sales orders still need buying
router.get(
  '/shortages',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const warehouseId = asString(req.query.warehouseId);
    ok(res, await buildShortagesReport(warehouseId, currentUser(req)));
  }),
);

// GET /reports/order-fulfilment — available vs. needed per open sales order
router.get(
  '/order-fulfilment',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const warehouseId = asString(req.query.warehouseId);
    ok(res, await buildOrderFulfilmentReport(warehouseId, currentUser(req)));
  }),
);

// GET /reports/low-stock
router.get(
  '/low-stock',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const rows = await lowStockProducts(asString(req.query.warehouseId));
    ok(
      res,
      rows.map((row) => ({
        ...row.product,
        costPrice: Number(row.product.costPrice),
        salePrice: Number(row.product.salePrice),
        quantity: row.quantity,
        shortage: row.shortage,
      })),
    );
  }),
);

// GET /reports/sales-by-customer
router.get(
  '/sales-by-customer',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const report = await buildSalesByCustomer(from, to, currentUser(req));
    ok(
      res,
      canViewProfit(currentUser(req))
        ? report
        : stripProfit(report, ['cost', 'profit']),
    );
  }),
);

// GET /reports/sales-by-category
router.get(
  '/sales-by-category',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const report = await buildSalesByCategory(from, to, currentUser(req));
    ok(res, canViewProfit(currentUser(req)) ? report : stripProfit(report, ['cost', 'profit']));
  }),
);

// GET /reports/sales-by-salesperson
router.get(
  '/sales-by-salesperson',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    ok(res, await buildSalesBySalesperson(from, to, currentUser(req)));
  }),
);

// GET /reports/purchases-by-supplier
router.get(
  '/purchases-by-supplier',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    ok(res, await buildPurchasesBySupplier(from, to));
  }),
);

// GET /reports/returns?type=CUSTOMER_RETURN|SUPPLIER_RETURN
router.get(
  '/returns',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const user = currentUser(req);
    // Representatives see only their customers' returns, never supplier returns.
    const type = isSalesperson(user) ? 'CUSTOMER_RETURN' : asString(req.query.type);
    ok(res, await buildReturnsReport(from, to, type, user));
  }),
);

// GET /reports/cash-flow
router.get(
  '/cash-flow',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    ok(res, await buildCashFlowReport(from, to));
  }),
);

// GET /reports/dead-stock?days=90
router.get(
  '/dead-stock',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const days = Number(asString(req.query.days) ?? 90);
    ok(res, await buildDeadStockReport(days));
  }),
);

// GET /reports/payments-by-method
router.get(
  '/payments-by-method',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    ok(res, await buildPaymentsByMethod(from, to));
  }),
);

// GET /reports/general-ledger?accountId=&from=&to=
router.get(
  '/general-ledger',
  requirePermission('accounting.read'),
  asyncHandler(async (req, res) => {
    const accountId = asString(req.query.accountId);
    if (!accountId) throw ApiError.badRequest('accountId is required');
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const account = await prisma.account.findUnique({
      where: { id: accountId },
      select: { id: true, code: true, name: true, type: true },
    });
    if (!account) throw ApiError.notFound('Account not found');

    const [openingLines, lines] = await Promise.all([
      from
        ? prisma.journalLine.findMany({
            where: { accountId, journalEntry: { entryDate: { lt: from } } },
            select: { debit: true, credit: true },
          })
        : Promise.resolve([] as { debit: Prisma.Decimal; credit: Prisma.Decimal }[]),
      prisma.journalLine.findMany({
        where: {
          accountId,
          ...(from || to
            ? {
                journalEntry: {
                  ...(from || to
                    ? {
                        entryDate: {
                          ...(from ? { gte: from } : {}),
                          ...(to ? { lte: to } : {}),
                        },
                      }
                    : {}),
                },
              }
            : {}),
        },
        orderBy: [{ journalEntry: { entryDate: 'asc' } }, { journalEntry: { createdAt: 'asc' } }],
        include: {
          journalEntry: {
            select: {
              id: true,
              number: true,
              memo: true,
              reference: true,
              entryDate: true,
            },
          },
        },
      }),
    ]);

    let running = round2(
      openingLines.reduce(
        (sum, line) => sum + Number(line.debit) - Number(line.credit),
        0,
      ),
    );
    const opening = running;
    const rows = lines.map((line) => {
      const debit = round2(Number(line.debit));
      const credit = round2(Number(line.credit));
      running = round2(running + debit - credit);
      return {
        id: line.id,
        date: line.journalEntry.entryDate,
        entryNumber: line.journalEntry.number,
        memo: line.journalEntry.memo,
        reference: line.journalEntry.reference,
        description: line.description,
        debit,
        credit,
        balance: running,
      };
    });
    const totals = rows.reduce(
      (acc, row) => ({
        debit: round2(acc.debit + row.debit),
        credit: round2(acc.credit + row.credit),
      }),
      { debit: 0, credit: 0 },
    );

    ok(res, {
      account,
      from: from ? dayKey(from) : null,
      to: to ? dayKey(to) : null,
      opening,
      rows,
      totals,
    });
  }),
);

// GET /reports/backup — a full .xlsx workbook of every business record.
// Admin-only (settings.write is withheld from every other role).
router.get(
  '/backup',
  requirePermission('settings.write'),
  asyncHandler(async (_req, res) => {
    const buffer = await buildBackupWorkbook();
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
    res.set(
      'Content-Type',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    res.set('Content-Disposition', `attachment; filename="erp-backup-${stamp}.xlsx"`);
    res.set('Content-Length', String(buffer.length));
    res.end(buffer);
  }),
);

export default router;
