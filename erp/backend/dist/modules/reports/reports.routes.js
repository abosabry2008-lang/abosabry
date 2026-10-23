"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const api_error_1 = require("../../lib/api-error");
const http_1 = require("../../lib/http");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const query_1 = require("../../lib/query");
const authenticate_token_1 = require("../../middleware/authenticate-token");
const authorize_1 = require("../../middleware/authorize");
const inventory_service_1 = require("../inventory/inventory.service");
const reports_service_1 = require("./reports.service");
const statement_service_1 = require("./statement.service");
const backup_service_1 = require("./backup.service");
const analytics_service_1 = require("./analytics.service");
const salespeople_service_1 = require("./salespeople.service");
const router = (0, express_1.Router)();
// Accepts the bearer header for JSON calls and `?token=` for links opened in a
// browser (e.g. the Excel backup download).
router.use(authenticate_token_1.authenticateToken);
function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}
// GET /reports/dashboard
router.get('/dashboard', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    const now = new Date();
    const todayStart = startOfDay(now);
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const last30 = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const weekStart = new Date(todayStart.getTime() - 6 * 24 * 60 * 60 * 1000);
    const [productCount, customerCount, supplierCount, warehouseCount, salesToday, salesMonth, receivables, payables, levels, lowStock, recentMovements, salesLines, recentOrders,] = await Promise.all([
        prisma_1.prisma.product.count({ where: { deletedAt: null, active: true } }),
        prisma_1.prisma.customer.count({ where: { active: true } }),
        prisma_1.prisma.supplier.count({ where: { active: true } }),
        prisma_1.prisma.warehouse.count({ where: { active: true } }),
        prisma_1.prisma.salesOrder.aggregate({
            where: { orderDate: { gte: todayStart }, status: { not: 'CANCELLED' } },
            _sum: { total: true },
            _count: { _all: true },
        }),
        prisma_1.prisma.salesOrder.aggregate({
            where: { orderDate: { gte: monthStart }, status: { not: 'CANCELLED' } },
            _sum: { total: true },
            _count: { _all: true },
        }),
        prisma_1.prisma.invoice.aggregate({
            where: { status: { in: ['ISSUED', 'PARTIALLY_PAID'] } },
            _sum: { balance: true },
        }),
        prisma_1.prisma.supplier.aggregate({ _sum: { balance: true } }),
        prisma_1.prisma.stockLevel.findMany({ select: { productId: true, quantity: true } }),
        (0, inventory_service_1.lowStockProducts)(),
        prisma_1.prisma.stockMovement.findMany({
            take: 10,
            orderBy: { createdAt: 'desc' },
            include: {
                product: { select: { id: true, sku: true, name: true } },
                location: { select: { id: true, code: true, name: true } },
            },
        }),
        prisma_1.prisma.salesOrderLine.findMany({
            where: {
                salesOrder: { orderDate: { gte: last30 }, status: { not: 'CANCELLED' } },
            },
            select: { productId: true, quantity: true, unitPrice: true },
        }),
        prisma_1.prisma.salesOrder.findMany({
            where: { orderDate: { gte: weekStart }, status: { not: 'CANCELLED' } },
            select: { orderDate: true, total: true },
        }),
    ]);
    const productIds = [...new Set(levels.map((level) => level.productId))];
    const products = productIds.length
        ? await prisma_1.prisma.product.findMany({
            where: { id: { in: productIds } },
            select: { id: true, costPrice: true, salePrice: true },
        })
        : [];
    const priceById = new Map(products.map((product) => [
        product.id,
        { cost: Number(product.costPrice), sale: Number(product.salePrice) },
    ]));
    let stockUnits = 0;
    let stockCostValue = 0;
    let stockRetailValue = 0;
    for (const level of levels) {
        const prices = priceById.get(level.productId);
        stockUnits += level.quantity;
        stockCostValue += level.quantity * (prices?.cost ?? 0);
        stockRetailValue += level.quantity * (prices?.sale ?? 0);
    }
    const topMap = new Map();
    for (const line of salesLines) {
        const entry = topMap.get(line.productId) ?? { quantity: 0, revenue: 0 };
        entry.quantity += line.quantity;
        entry.revenue += line.quantity * Number(line.unitPrice);
        topMap.set(line.productId, entry);
    }
    const topIds = [...topMap.entries()].sort((a, b) => b[1].revenue - a[1].revenue).slice(0, 5);
    const topProducts = topIds.length
        ? await prisma_1.prisma.product.findMany({
            where: { id: { in: topIds.map(([id]) => id) } },
            select: { id: true, sku: true, name: true },
        })
        : [];
    const topNameById = new Map(topProducts.map((product) => [product.id, product]));
    const series = [];
    for (let i = 6; i >= 0; i -= 1) {
        const day = new Date(todayStart.getTime() - i * 24 * 60 * 60 * 1000);
        series.push({ date: (0, reports_service_1.dayKey)(day), total: 0, orders: 0 });
    }
    const seriesByDate = new Map(series.map((point) => [point.date, point]));
    for (const order of recentOrders) {
        const point = seriesByDate.get((0, reports_service_1.dayKey)(order.orderDate));
        if (point) {
            point.total = (0, money_1.round2)(point.total + Number(order.total));
            point.orders += 1;
        }
    }
    (0, http_1.ok)(res, {
        counts: {
            products: productCount,
            customers: customerCount,
            suppliers: supplierCount,
            warehouses: warehouseCount,
            lowStock: lowStock.length,
        },
        inventory: {
            units: stockUnits,
            costValue: (0, money_1.round2)(stockCostValue),
            retailValue: (0, money_1.round2)(stockRetailValue),
        },
        sales: {
            today: (0, money_1.round2)(Number(salesToday._sum.total ?? 0)),
            todayOrders: salesToday._count._all,
            month: (0, money_1.round2)(Number(salesMonth._sum.total ?? 0)),
            monthOrders: salesMonth._count._all,
        },
        receivables: (0, money_1.round2)(Number(receivables._sum.balance ?? 0)),
        payables: (0, money_1.round2)(Number(payables._sum.balance ?? 0)),
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
            revenue: (0, money_1.round2)(stats.revenue),
        })),
        salesSeries: series,
        recentMovements: recentMovements.map((movement) => ({
            ...movement,
            unitCost: Number(movement.unitCost),
        })),
    });
}));
// GET /reports/sales
router.get('/sales', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const groupBy = (0, query_1.asString)(req.query.groupBy) === 'month' ? 'month' : 'day';
    (0, http_1.ok)(res, await (0, reports_service_1.buildSalesReport)(from, to, groupBy));
}));
// GET /reports/inventory-valuation
router.get('/inventory-valuation', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouseId = (0, query_1.asString)(req.query.warehouseId);
    (0, http_1.ok)(res, await (0, reports_service_1.buildInventoryValuation)(warehouseId));
}));
// GET /reports/top-products
router.get('/top-products', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const limit = Number((0, query_1.asString)(req.query.limit) ?? 10);
    (0, http_1.ok)(res, await (0, reports_service_1.buildTopProducts)(from, to, limit));
}));
// GET /reports/customer-balances
router.get('/customer-balances', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    const customers = await prisma_1.prisma.customer.findMany({
        where: { balance: { not: 0 } },
        orderBy: { balance: 'desc' },
        include: { _count: { select: { invoices: true } } },
    });
    (0, http_1.ok)(res, customers.map((customer) => ({
        id: customer.id,
        name: customer.name,
        email: customer.email,
        phone: customer.phone,
        creditLimit: Number(customer.creditLimit),
        balance: Number(customer.balance),
        invoices: customer._count.invoices,
    })));
}));
// GET /reports/supplier-balances
router.get('/supplier-balances', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    const suppliers = await prisma_1.prisma.supplier.findMany({
        where: { balance: { not: 0 } },
        orderBy: { balance: 'desc' },
        include: { _count: { select: { purchaseOrders: true } } },
    });
    (0, http_1.ok)(res, suppliers.map((supplier) => ({
        id: supplier.id,
        name: supplier.name,
        email: supplier.email,
        phone: supplier.phone,
        balance: Number(supplier.balance),
        purchaseOrders: supplier._count.purchaseOrders,
    })));
}));
// GET /reports/receivables-by-salesperson
router.get('/receivables-by-salesperson', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const userId = (0, query_1.asString)(req.query.userId);
    (0, http_1.ok)(res, await (0, analytics_service_1.buildReceivablesBySalesperson)(from, to, userId));
}));
// GET /reports/supplier-payables
router.get('/supplier-payables', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    (0, http_1.ok)(res, await (0, analytics_service_1.buildSupplierPayables)(from, to));
}));
// GET /reports/consolidated-sales-note
router.get('/consolidated-sales-note', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const salespersonId = (0, query_1.asString)(req.query.salespersonId);
    (0, http_1.ok)(res, await (0, salespeople_service_1.buildConsolidatedSalesNote)(from, to, salespersonId));
}));
// GET /reports/profit-by-salesperson
router.get('/profit-by-salesperson', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const salespersonId = (0, query_1.asString)(req.query.salespersonId);
    (0, http_1.ok)(res, await (0, salespeople_service_1.buildProfitBySalesperson)(from, to, salespersonId));
}));
// GET /reports/collections-by-salesperson
router.get('/collections-by-salesperson', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const salespersonId = (0, query_1.asString)(req.query.salespersonId);
    (0, http_1.ok)(res, await (0, salespeople_service_1.buildCollectionsBySalesperson)(from, to, salespersonId));
}));
// GET /reports/salespeople/:id/statement
router.get('/salespeople/:id/statement', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    try {
        (0, http_1.ok)(res, await (0, salespeople_service_1.buildSalespersonStatement)(req.params.id, from, to));
    }
    catch (error) {
        if (error instanceof Error && error.message === 'SALESPERSON_NOT_FOUND') {
            throw api_error_1.ApiError.notFound('Salesperson not found', 'SALESPERSON_NOT_FOUND');
        }
        throw error;
    }
}));
// GET /reports/salespeople/:id/customers — per-customer debt ledger
router.get('/salespeople/:id/customers', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    try {
        (0, http_1.ok)(res, await (0, salespeople_service_1.buildSalespersonCustomerDebt)(req.params.id, from, to));
    }
    catch (error) {
        if (error instanceof Error && error.message === 'SALESPERSON_NOT_FOUND') {
            throw api_error_1.ApiError.notFound('Salesperson not found', 'SALESPERSON_NOT_FOUND');
        }
        throw error;
    }
}));
// GET /reports/stock-balance
router.get('/stock-balance', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouseId = (0, query_1.asString)(req.query.warehouseId);
    const categoryId = (0, query_1.asString)(req.query.categoryId);
    (0, http_1.ok)(res, await (0, analytics_service_1.buildStockBalance)(warehouseId, categoryId));
}));
// GET /reports/item-movement
router.get('/item-movement', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const productId = (0, query_1.asString)(req.query.productId);
    if (!productId)
        throw api_error_1.ApiError.badRequest('productId is required', 'PRODUCT_REQUIRED');
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const warehouseId = (0, query_1.asString)(req.query.warehouseId);
    (0, http_1.ok)(res, await (0, analytics_service_1.buildItemMovement)(productId, from, to, warehouseId));
}));
// GET /reports/customers/:id/statement
router.get('/customers/:id/statement', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    (0, http_1.ok)(res, await (0, statement_service_1.buildCustomerStatement)(req.params.id, from, to));
}));
// GET /reports/suppliers/:id/statement
router.get('/suppliers/:id/statement', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    (0, http_1.ok)(res, await (0, statement_service_1.buildSupplierStatement)(req.params.id, from, to));
}));
// GET /reports/purchases
router.get('/purchases', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const groupBy = (0, query_1.asString)(req.query.groupBy) === 'month' ? 'month' : 'day';
    (0, http_1.ok)(res, await (0, reports_service_1.buildPurchasesReport)(from, to, groupBy));
}));
// GET /reports/profit
router.get('/profit', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    (0, http_1.ok)(res, await (0, reports_service_1.buildProfitReport)(from, to));
}));
// GET /reports/tax
router.get('/tax', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    (0, http_1.ok)(res, await (0, reports_service_1.buildTaxReport)(from, to));
}));
// GET /reports/aging?side=receivable|payable
router.get('/aging', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const side = (0, query_1.asString)(req.query.side) === 'payable' ? 'payable' : 'receivable';
    const asOf = (0, query_1.asDate)(req.query.asOf);
    (0, http_1.ok)(res, await (0, analytics_service_1.buildAgingReport)(side, asOf));
}));
// GET /reports/shortages — what open sales orders still need buying
router.get('/shortages', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouseId = (0, query_1.asString)(req.query.warehouseId);
    (0, http_1.ok)(res, await (0, analytics_service_1.buildShortagesReport)(warehouseId));
}));
// GET /reports/order-fulfilment — available vs. needed per open sales order
router.get('/order-fulfilment', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouseId = (0, query_1.asString)(req.query.warehouseId);
    (0, http_1.ok)(res, await (0, analytics_service_1.buildOrderFulfilmentReport)(warehouseId));
}));
// GET /reports/low-stock
router.get('/low-stock', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const rows = await (0, inventory_service_1.lowStockProducts)((0, query_1.asString)(req.query.warehouseId));
    (0, http_1.ok)(res, rows.map((row) => ({
        ...row.product,
        costPrice: Number(row.product.costPrice),
        salePrice: Number(row.product.salePrice),
        quantity: row.quantity,
        shortage: row.shortage,
    })));
}));
// GET /reports/backup — a full .xlsx workbook of every business record.
// Admin-only (settings.write is withheld from every other role).
router.get('/backup', (0, authorize_1.requirePermission)('settings.write'), (0, http_1.asyncHandler)(async (_req, res) => {
    const buffer = await (0, backup_service_1.buildBackupWorkbook)();
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
    res.set('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.set('Content-Disposition', `attachment; filename="erp-backup-${stamp}.xlsx"`);
    res.set('Content-Length', String(buffer.length));
    res.end(buffer);
}));
exports.default = router;
//# sourceMappingURL=reports.routes.js.map