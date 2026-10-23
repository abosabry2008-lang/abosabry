"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.monthKey = exports.dayKey = void 0;
exports.buildSalesReport = buildSalesReport;
exports.buildInventoryValuation = buildInventoryValuation;
exports.buildTopProducts = buildTopProducts;
exports.buildPurchasesReport = buildPurchasesReport;
exports.buildProfitReport = buildProfitReport;
exports.buildTaxReport = buildTaxReport;
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const dayKey = (date) => date.toISOString().slice(0, 10);
exports.dayKey = dayKey;
const monthKey = (date) => date.toISOString().slice(0, 7);
exports.monthKey = monthKey;
/** Sales totals grouped by day or month. Defaults to the current year. */
async function buildSalesReport(fromInput, toInput, groupBy = 'day') {
    const now = new Date();
    const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
    const to = toInput ?? now;
    const orders = await prisma_1.prisma.salesOrder.findMany({
        where: { orderDate: { gte: from, lte: to }, status: { not: 'CANCELLED' } },
        select: { orderDate: true, subtotal: true, taxTotal: true, discountTotal: true, total: true },
    });
    const buckets = new Map();
    let subtotal = 0;
    let tax = 0;
    let discount = 0;
    let total = 0;
    for (const order of orders) {
        const key = groupBy === 'month' ? (0, exports.monthKey)(order.orderDate) : (0, exports.dayKey)(order.orderDate);
        const bucket = buckets.get(key) ??
            { period: key, orders: 0, subtotal: 0, tax: 0, discount: 0, total: 0 };
        bucket.orders += 1;
        bucket.subtotal = (0, money_1.round2)(bucket.subtotal + Number(order.subtotal));
        bucket.tax = (0, money_1.round2)(bucket.tax + Number(order.taxTotal));
        bucket.discount = (0, money_1.round2)(bucket.discount + Number(order.discountTotal));
        bucket.total = (0, money_1.round2)(bucket.total + Number(order.total));
        buckets.set(key, bucket);
        subtotal += Number(order.subtotal);
        tax += Number(order.taxTotal);
        discount += Number(order.discountTotal);
        total += Number(order.total);
    }
    return {
        from: (0, exports.dayKey)(from),
        to: (0, exports.dayKey)(to),
        groupBy,
        totals: {
            orders: orders.length,
            subtotal: (0, money_1.round2)(subtotal),
            tax: (0, money_1.round2)(tax),
            discount: (0, money_1.round2)(discount),
            total: (0, money_1.round2)(total),
        },
        series: [...buckets.values()].sort((a, b) => a.period.localeCompare(b.period)),
    };
}
/** Stock-on-hand valuation, optionally limited to a single warehouse. */
async function buildInventoryValuation(warehouseId) {
    const levels = await prisma_1.prisma.stockLevel.findMany({
        where: warehouseId ? { warehouseId } : {},
        orderBy: [{ warehouseId: 'asc' }, { productId: 'asc' }],
        include: {
            product: { select: { id: true, sku: true, name: true, unit: true, costPrice: true, salePrice: true } },
            warehouse: { select: { id: true, code: true, name: true } },
            location: { select: { id: true, code: true, name: true } },
        },
    });
    const rows = levels
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
            costValue: (0, money_1.round2)(level.quantity * cost),
            retailValue: (0, money_1.round2)(level.quantity * sale),
        };
    });
    return {
        rows,
        totals: {
            lines: rows.length,
            units: rows.reduce((sum, row) => sum + row.quantity, 0),
            costValue: (0, money_1.round2)(rows.reduce((sum, row) => sum + row.costValue, 0)),
            retailValue: (0, money_1.round2)(rows.reduce((sum, row) => sum + row.retailValue, 0)),
        },
    };
}
/** Best-selling products by revenue over a date range. Defaults to the last 30 days. */
async function buildTopProducts(fromInput, toInput, limitInput = 10) {
    const now = new Date();
    const from = fromInput ?? new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const to = toInput ?? now;
    const limit = Number.isFinite(limitInput) ? Math.min(100, Math.max(1, Math.floor(limitInput))) : 10;
    const lines = await prisma_1.prisma.salesOrderLine.findMany({
        where: { salesOrder: { orderDate: { gte: from, lte: to }, status: { not: 'CANCELLED' } } },
        select: { productId: true, quantity: true, unitPrice: true, salesOrderId: true },
    });
    const byProduct = new Map();
    for (const line of lines) {
        const entry = byProduct.get(line.productId) ?? { quantity: 0, revenue: 0, orders: new Set() };
        entry.quantity += line.quantity;
        entry.revenue += line.quantity * Number(line.unitPrice);
        entry.orders.add(line.salesOrderId);
        byProduct.set(line.productId, entry);
    }
    const ranked = [...byProduct.entries()].sort((a, b) => b[1].revenue - a[1].revenue).slice(0, limit);
    const products = ranked.length
        ? await prisma_1.prisma.product.findMany({
            where: { id: { in: ranked.map(([id]) => id) } },
            select: { id: true, sku: true, name: true },
        })
        : [];
    const byId = new Map(products.map((product) => [product.id, product]));
    return {
        from: (0, exports.dayKey)(from),
        to: (0, exports.dayKey)(to),
        rows: ranked.map(([productId, stats]) => ({
            productId,
            sku: byId.get(productId)?.sku ?? '',
            name: byId.get(productId)?.name ?? '',
            quantitySold: stats.quantity,
            revenue: (0, money_1.round2)(stats.revenue),
            orders: stats.orders.size,
        })),
    };
}
/** Purchase order totals grouped by day or month. Defaults to the current year. */
async function buildPurchasesReport(fromInput, toInput, groupBy = 'day') {
    const now = new Date();
    const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
    const to = toInput ?? now;
    const orders = await prisma_1.prisma.purchaseOrder.findMany({
        where: { orderDate: { gte: from, lte: to }, status: { not: 'CANCELLED' } },
        select: { orderDate: true, subtotal: true, taxTotal: true, total: true },
    });
    const buckets = new Map();
    let subtotal = 0;
    let tax = 0;
    let total = 0;
    for (const order of orders) {
        const key = groupBy === 'month' ? (0, exports.monthKey)(order.orderDate) : (0, exports.dayKey)(order.orderDate);
        const bucket = buckets.get(key) ?? { period: key, orders: 0, subtotal: 0, tax: 0, total: 0 };
        bucket.orders += 1;
        bucket.subtotal = (0, money_1.round2)(bucket.subtotal + Number(order.subtotal));
        bucket.tax = (0, money_1.round2)(bucket.tax + Number(order.taxTotal));
        bucket.total = (0, money_1.round2)(bucket.total + Number(order.total));
        buckets.set(key, bucket);
        subtotal += Number(order.subtotal);
        tax += Number(order.taxTotal);
        total += Number(order.total);
    }
    return {
        from: (0, exports.dayKey)(from),
        to: (0, exports.dayKey)(to),
        groupBy,
        totals: {
            orders: orders.length,
            subtotal: (0, money_1.round2)(subtotal),
            tax: (0, money_1.round2)(tax),
            total: (0, money_1.round2)(total),
        },
        series: [...buckets.values()].sort((a, b) => a.period.localeCompare(b.period)),
    };
}
/** Revenue (net of tax) minus product cost for issued invoices in a period. */
async function buildProfitReport(fromInput, toInput) {
    const now = new Date();
    const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
    const to = toInput ?? now;
    const invoices = await prisma_1.prisma.invoice.findMany({
        where: { status: { notIn: ['DRAFT', 'VOID'] }, issueDate: { gte: from, lte: to } },
        select: {
            id: true,
            lines: {
                select: {
                    productId: true,
                    quantity: true,
                    unitPrice: true,
                    discount: true,
                    product: { select: { sku: true, name: true, costPrice: true } },
                },
            },
        },
    });
    const byProduct = new Map();
    let revenue = 0;
    let cost = 0;
    for (const invoice of invoices) {
        for (const line of invoice.lines) {
            const net = Math.max(0, (0, money_1.round2)(line.quantity * Number(line.unitPrice) - Number(line.discount)));
            const unitCost = line.product ? Number(line.product.costPrice) : 0;
            const lineCost = (0, money_1.round2)(line.quantity * unitCost);
            revenue += net;
            cost += lineCost;
            if (!line.productId || !line.product)
                continue;
            const row = byProduct.get(line.productId) ?? {
                productId: line.productId,
                sku: line.product.sku,
                name: line.product.name,
                quantity: 0,
                revenue: 0,
                cost: 0,
                profit: 0,
            };
            row.quantity += line.quantity;
            row.revenue = (0, money_1.round2)(row.revenue + net);
            row.cost = (0, money_1.round2)(row.cost + lineCost);
            byProduct.set(line.productId, row);
        }
    }
    const rows = [...byProduct.values()]
        .map((row) => ({ ...row, profit: (0, money_1.round2)(row.revenue - row.cost) }))
        .sort((a, b) => b.profit - a.profit);
    const profit = (0, money_1.round2)(revenue - cost);
    return {
        from: (0, exports.dayKey)(from),
        to: (0, exports.dayKey)(to),
        totals: {
            invoices: invoices.length,
            revenue: (0, money_1.round2)(revenue),
            cost: (0, money_1.round2)(cost),
            profit,
            margin: revenue > 0 ? (0, money_1.round2)((profit / revenue) * 100) : 0,
        },
        rows,
    };
}
/** Output tax charged on invoices minus input tax on purchase orders. */
async function buildTaxReport(fromInput, toInput) {
    const now = new Date();
    const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
    const to = toInput ?? now;
    const [invoices, purchaseOrders] = await Promise.all([
        prisma_1.prisma.invoice.findMany({
            where: { status: { notIn: ['DRAFT', 'VOID'] }, issueDate: { gte: from, lte: to } },
            select: { issueDate: true, taxTotal: true, total: true },
        }),
        prisma_1.prisma.purchaseOrder.findMany({
            where: { status: { not: 'CANCELLED' }, orderDate: { gte: from, lte: to } },
            select: { orderDate: true, taxTotal: true, total: true },
        }),
    ]);
    const buckets = new Map();
    let salesTax = 0;
    let purchaseTax = 0;
    let taxableSales = 0;
    let taxablePurchases = 0;
    const bucketFor = (key) => {
        const existing = buckets.get(key);
        if (existing)
            return existing;
        const created = { period: key, salesTax: 0, purchaseTax: 0, netTax: 0 };
        buckets.set(key, created);
        return created;
    };
    for (const invoice of invoices) {
        const amount = Number(invoice.taxTotal);
        salesTax += amount;
        taxableSales += Number(invoice.total);
        const bucket = bucketFor((0, exports.monthKey)(invoice.issueDate));
        bucket.salesTax = (0, money_1.round2)(bucket.salesTax + amount);
    }
    for (const order of purchaseOrders) {
        const amount = Number(order.taxTotal);
        purchaseTax += amount;
        taxablePurchases += Number(order.total);
        const bucket = bucketFor((0, exports.monthKey)(order.orderDate));
        bucket.purchaseTax = (0, money_1.round2)(bucket.purchaseTax + amount);
    }
    const series = [...buckets.values()]
        .map((bucket) => ({ ...bucket, netTax: (0, money_1.round2)(bucket.salesTax - bucket.purchaseTax) }))
        .sort((a, b) => a.period.localeCompare(b.period));
    return {
        from: (0, exports.dayKey)(from),
        to: (0, exports.dayKey)(to),
        totals: {
            salesTax: (0, money_1.round2)(salesTax),
            purchaseTax: (0, money_1.round2)(purchaseTax),
            netTax: (0, money_1.round2)(salesTax - purchaseTax),
            taxableSales: (0, money_1.round2)(taxableSales),
            taxablePurchases: (0, money_1.round2)(taxablePurchases),
        },
        series,
    };
}
//# sourceMappingURL=reports.service.js.map