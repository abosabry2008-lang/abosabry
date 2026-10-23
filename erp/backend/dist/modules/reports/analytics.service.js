"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildReceivablesBySalesperson = buildReceivablesBySalesperson;
exports.buildSupplierPayables = buildSupplierPayables;
exports.buildStockBalance = buildStockBalance;
exports.buildItemMovement = buildItemMovement;
exports.buildAgingReport = buildAgingReport;
exports.buildShortagesReport = buildShortagesReport;
exports.buildOrderFulfilmentReport = buildOrderFulfilmentReport;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
/** Outstanding customer balances attributed to the salesperson on the order. */
async function buildReceivablesBySalesperson(fromInput, toInput, userId) {
    const dateWhere = {};
    if (fromInput || toInput) {
        dateWhere.issueDate = {
            ...(fromInput ? { gte: fromInput } : {}),
            ...(toInput ? { lte: toInput } : {}),
        };
    }
    const invoices = await prisma_1.prisma.invoice.findMany({
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
    const map = new Map();
    for (const invoice of invoices) {
        // The customer's assigned representative wins; otherwise the order's creator.
        const rep = invoice.customer?.salesperson ?? invoice.salesOrder?.user ?? null;
        const customer = invoice.customer;
        const key = `${rep?.id ?? '-'}::${customer?.id ?? '-'}`;
        const row = map.get(key) ??
            {
                salespersonId: rep?.id ?? null,
                salesperson: rep?.name ?? null,
                customerId: customer?.id ?? null,
                customer: customer?.name ?? null,
                invoices: 0,
                total: 0,
                paid: 0,
                balance: 0,
            };
        row.invoices += 1;
        row.total = (0, money_1.round2)(row.total + Number(invoice.total));
        row.paid = (0, money_1.round2)(row.paid + Number(invoice.amountPaid));
        row.balance = (0, money_1.round2)(row.balance + Number(invoice.balance));
        map.set(key, row);
    }
    const rows = [...map.values()].sort((a, b) => (a.salesperson ?? '').localeCompare(b.salesperson ?? '') || b.balance - a.balance);
    const totals = rows.reduce((acc, row) => ({
        invoices: acc.invoices + row.invoices,
        total: (0, money_1.round2)(acc.total + row.total),
        paid: (0, money_1.round2)(acc.paid + row.paid),
        balance: (0, money_1.round2)(acc.balance + row.balance),
    }), { invoices: 0, total: 0, paid: 0, balance: 0 });
    return {
        from: fromInput ? fromInput.toISOString() : null,
        to: toInput ? toInput.toISOString() : null,
        rows,
        totals,
    };
}
/** Every supplier with a non-zero balance or purchases in the period. */
async function buildSupplierPayables(fromInput, toInput) {
    const dateRange = fromInput || toInput
        ? {
            ...(fromInput ? { gte: fromInput } : {}),
            ...(toInput ? { lte: toInput } : {}),
        }
        : undefined;
    const [suppliers, purchaseGroups, paymentGroups] = await Promise.all([
        prisma_1.prisma.supplier.findMany({
            select: { id: true, name: true, phone: true, balance: true },
        }),
        prisma_1.prisma.purchaseOrder.groupBy({
            by: ['supplierId'],
            where: { status: { not: 'CANCELLED' }, ...(dateRange ? { orderDate: dateRange } : {}) },
            _sum: { total: true },
            _count: { _all: true },
        }),
        prisma_1.prisma.payment.groupBy({
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
    const purchasesById = new Map(purchaseGroups.map((group) => [
        group.supplierId,
        { total: (0, money_1.round2)(Number(group._sum.total ?? 0)), count: group._count._all },
    ]));
    const paidById = new Map(paymentGroups.map((group) => [group.supplierId ?? '', (0, money_1.round2)(Number(group._sum.amount ?? 0))]));
    const rows = [];
    for (const supplier of suppliers) {
        const purchases = purchasesById.get(supplier.id) ?? { total: 0, count: 0 };
        const paid = paidById.get(supplier.id) ?? 0;
        const balance = (0, money_1.round2)(Number(supplier.balance));
        if (balance === 0 && purchases.total === 0)
            continue;
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
    const totals = rows.reduce((acc, row) => ({
        purchaseOrders: acc.purchaseOrders + row.purchaseOrders,
        purchases: (0, money_1.round2)(acc.purchases + row.purchases),
        paid: (0, money_1.round2)(acc.paid + row.paid),
        balance: (0, money_1.round2)(acc.balance + row.balance),
    }), { purchaseOrders: 0, purchases: 0, paid: 0, balance: 0 });
    return {
        from: fromInput ? fromInput.toISOString() : null,
        to: toInput ? toInput.toISOString() : null,
        rows,
        totals,
    };
}
/** On-hand quantity and value per product/warehouse, for counting and review. */
async function buildStockBalance(warehouseId, categoryId) {
    const levels = await prisma_1.prisma.stockLevel.findMany({
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
    const map = new Map();
    for (const level of levels) {
        const key = `${level.productId}::${level.warehouseId}`;
        const row = map.get(key) ??
            {
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
            };
        row.quantity += level.quantity;
        row.reserved += level.reserved;
        map.set(key, row);
    }
    const rows = [...map.values()].filter((row) => row.quantity !== 0 || row.reserved !== 0);
    for (const row of rows) {
        row.available = row.quantity - row.reserved;
        row.costValue = (0, money_1.round2)(row.quantity * row.unitCost);
        row.retailValue = (0, money_1.round2)(row.quantity * row.salePrice);
    }
    rows.sort((a, b) => a.name.localeCompare(b.name) || a.warehouse.localeCompare(b.warehouse));
    const totals = rows.reduce((acc, row) => ({
        quantity: acc.quantity + row.quantity,
        reserved: acc.reserved + row.reserved,
        available: acc.available + row.available,
        costValue: (0, money_1.round2)(acc.costValue + row.costValue),
        retailValue: (0, money_1.round2)(acc.retailValue + row.retailValue),
    }), { quantity: 0, reserved: 0, available: 0, costValue: 0, retailValue: 0 });
    return { rows, totals };
}
/** Every movement of one product with a running quantity balance. */
async function buildItemMovement(productId, fromInput, toInput, warehouseId) {
    const product = await prisma_1.prisma.product.findUnique({
        where: { id: productId },
        select: { id: true, sku: true, name: true, unit: true, costPrice: true },
    });
    if (!product)
        throw api_error_1.ApiError.notFound('Product not found');
    const base = {
        productId,
        ...(warehouseId ? { warehouseId } : {}),
    };
    const [openingRows, movements, warehouses] = await Promise.all([
        fromInput
            ? prisma_1.prisma.stockMovement.findMany({
                where: { ...base, createdAt: { lt: fromInput } },
                select: { quantity: true, unitCost: true },
            })
            : Promise.resolve([]),
        prisma_1.prisma.stockMovement.findMany({
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
        prisma_1.prisma.warehouse.findMany({ select: { id: true, name: true } }),
    ]);
    const warehouseById = new Map(warehouses.map((warehouse) => [warehouse.id, warehouse.name]));
    let openingQty = 0;
    let openingValue = 0;
    for (const movement of openingRows) {
        openingQty += movement.quantity;
        openingValue += movement.quantity * Number(movement.unitCost);
    }
    openingValue = (0, money_1.round2)(openingValue);
    let running = openingQty;
    let inQty = 0;
    let outQty = 0;
    let inValue = 0;
    let outValue = 0;
    const rows = movements.map((movement) => {
        const value = (0, money_1.round2)(movement.quantity * Number(movement.unitCost));
        running += movement.quantity;
        if (movement.quantity >= 0) {
            inQty += movement.quantity;
            inValue = (0, money_1.round2)(inValue + value);
        }
        else {
            outQty += -movement.quantity;
            outValue = (0, money_1.round2)(outValue - value);
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
    const closingValue = (0, money_1.round2)(openingValue + inValue - outValue);
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
const DAY_MS = 24 * 60 * 60 * 1000;
function emptyBuckets() {
    return { current: 0, d1_30: 0, d31_60: 0, d61_90: 0, d90_plus: 0, total: 0 };
}
/**
 * Outstanding balances split by how overdue they are.
 * Receivables age by invoice due date; payables (no due dates are recorded on
 * purchase orders) are reported as not yet due.
 */
async function buildAgingReport(side, asOfInput) {
    const asOf = asOfInput ?? new Date();
    const map = new Map();
    const rowFor = (id, name, phone) => {
        const existing = map.get(id);
        if (existing)
            return existing;
        const row = { id, name, phone, invoices: 0, oldestDueDate: null, ...emptyBuckets() };
        map.set(id, row);
        return row;
    };
    const addToBucket = (row, daysOverdue, amount) => {
        if (daysOverdue <= 0)
            row.current = (0, money_1.round2)(row.current + amount);
        else if (daysOverdue <= 30)
            row.d1_30 = (0, money_1.round2)(row.d1_30 + amount);
        else if (daysOverdue <= 60)
            row.d31_60 = (0, money_1.round2)(row.d31_60 + amount);
        else if (daysOverdue <= 90)
            row.d61_90 = (0, money_1.round2)(row.d61_90 + amount);
        else
            row.d90_plus = (0, money_1.round2)(row.d90_plus + amount);
        row.total = (0, money_1.round2)(row.total + amount);
    };
    if (side === 'receivable') {
        const invoices = await prisma_1.prisma.invoice.findMany({
            where: { status: { in: ['ISSUED', 'PARTIALLY_PAID'] }, balance: { not: 0 } },
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
                if (row.oldestDueDate == null || iso < row.oldestDueDate)
                    row.oldestDueDate = iso;
            }
        }
        // Customers whose stored balance is not fully explained by their invoices
        // carry an opening balance (or an un-invoiced adjustment). Include that
        // remainder so customers created with an opening balance show up here too.
        const customers = await prisma_1.prisma.customer.findMany({
            where: { balance: { not: 0 } },
            select: { id: true, name: true, phone: true, balance: true },
        });
        const invoicedByCustomer = await prisma_1.prisma.invoice.groupBy({
            by: ['customerId'],
            where: { status: { in: ['ISSUED', 'PARTIALLY_PAID'] }, customerId: { not: null } },
            _sum: { balance: true },
        });
        const invoicedMap = new Map();
        for (const group of invoicedByCustomer) {
            if (group.customerId)
                invoicedMap.set(group.customerId, Number(group._sum.balance ?? 0));
        }
        for (const customer of customers) {
            const remainder = (0, money_1.round2)(Number(customer.balance) - (invoicedMap.get(customer.id) ?? 0));
            if (remainder === 0)
                continue;
            const row = rowFor(customer.id, customer.name, customer.phone);
            // No due date is recorded for an opening balance: report it as not yet due.
            addToBucket(row, 0, remainder);
        }
    }
    else {
        const suppliers = await prisma_1.prisma.supplier.findMany({
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
    const totals = rows.reduce((acc, row) => ({
        invoices: acc.invoices + row.invoices,
        current: (0, money_1.round2)(acc.current + row.current),
        d1_30: (0, money_1.round2)(acc.d1_30 + row.d1_30),
        d31_60: (0, money_1.round2)(acc.d31_60 + row.d31_60),
        d61_90: (0, money_1.round2)(acc.d61_90 + row.d61_90),
        d90_plus: (0, money_1.round2)(acc.d90_plus + row.d90_plus),
        total: (0, money_1.round2)(acc.total + row.total),
    }), { invoices: 0, current: 0, d1_30: 0, d31_60: 0, d61_90: 0, d90_plus: 0, total: 0 });
    return { side, asOf: asOf.toISOString(), rows, totals };
}
/**
 * Lists the products that open sales orders still need but that are not (fully)
 * on hand, so the shop knows exactly what to purchase to keep going.
 *
 * "Open" orders are any that are not cancelled and not fully fulfilled. For
 * each line we look at what is still to be delivered (`quantity - fulfilledQty`)
 * and compare it against the physical stock on hand.
 */
async function buildShortagesReport(warehouseId) {
    const lines = await prisma_1.prisma.salesOrderLine.findMany({
        where: {
            salesOrder: {
                status: { in: ['DRAFT', 'CONFIRMED', 'PARTIALLY_FULFILLED'] },
                ...(warehouseId ? { warehouseId } : {}),
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
                },
            },
        },
    });
    const levels = await prisma_1.prisma.stockLevel.findMany({
        where: warehouseId ? { warehouseId } : {},
        select: { productId: true, quantity: true, reserved: true },
    });
    const onHandById = new Map();
    for (const level of levels) {
        const available = level.quantity - level.reserved;
        onHandById.set(level.productId, (0, money_1.round2)((onHandById.get(level.productId) ?? 0) + available));
    }
    const map = new Map();
    for (const line of lines) {
        const outstanding = line.quantity - line.fulfilledQty;
        if (outstanding <= 0)
            continue;
        const row = map.get(line.productId) ??
            {
                productId: line.productId,
                sku: line.product.sku,
                name: line.product.name,
                unit: line.product.unit,
                onHand: onHandById.get(line.productId) ?? 0,
                required: 0,
                shortage: 0,
                unitCost: Number(line.product.costPrice),
                purchaseValue: 0,
                orders: [],
            };
        row.required = (0, money_1.round2)(row.required + outstanding);
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
        row.shortage = (0, money_1.round2)(Math.max(0, row.required - row.onHand));
        row.purchaseValue = (0, money_1.round2)(row.shortage * row.unitCost);
        row.orders.sort((a, b) => a.orderDate.localeCompare(b.orderDate));
    }
    // Only surface products that are actually short; fully-covered products are
    // still returned with `shortage: 0` only when nothing at all is missing.
    const shortRows = rows
        .filter((row) => row.shortage > 0)
        .sort((a, b) => b.purchaseValue - a.purchaseValue || a.name.localeCompare(b.name));
    const totals = shortRows.reduce((acc, row) => ({
        products: acc.products + 1,
        required: (0, money_1.round2)(acc.required + row.required),
        onHand: (0, money_1.round2)(acc.onHand + row.onHand),
        shortage: (0, money_1.round2)(acc.shortage + row.shortage),
        purchaseValue: (0, money_1.round2)(acc.purchaseValue + row.purchaseValue),
    }), { products: 0, required: 0, onHand: 0, shortage: 0, purchaseValue: 0 });
    return {
        generatedAt: new Date().toISOString(),
        rows: shortRows,
        totals,
    };
}
/**
 * One row per open sales order showing, line by line, what is available on hand
 * (`available`), what the customer ordered (`required`) and what still has to be
 * purchased (`shortage`). This is the "goods available vs. goods to buy" board
 * for finishing the order.
 */
async function buildOrderFulfilmentReport(warehouseId) {
    const orders = await prisma_1.prisma.salesOrder.findMany({
        where: {
            status: { in: ['DRAFT', 'CONFIRMED', 'PARTIALLY_FULFILLED'] },
            ...(warehouseId ? { warehouseId } : {}),
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
    const levels = await prisma_1.prisma.stockLevel.findMany({
        where: warehouseId ? { warehouseId } : {},
        select: { productId: true, warehouseId: true, quantity: true, reserved: true },
    });
    const onHand = new Map();
    for (const level of levels) {
        const key = `${level.warehouseId}:${level.productId}`;
        const available = Number(level.quantity) - Number(level.reserved);
        onHand.set(key, (0, money_1.round2)((onHand.get(key) ?? 0) + available));
    }
    const rows = [];
    for (const order of orders) {
        const lines = [];
        for (const line of order.lines) {
            const required = line.quantity - line.fulfilledQty;
            if (required <= 0)
                continue;
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
                shortage: (0, money_1.round2)(Math.max(0, required - available)),
            });
        }
        if (lines.length === 0)
            continue;
        const totals = lines.reduce((acc, line) => ({
            required: (0, money_1.round2)(acc.required + line.required),
            available: (0, money_1.round2)(acc.available + line.available),
            shortage: (0, money_1.round2)(acc.shortage + line.shortage),
        }), { required: 0, available: 0, shortage: 0 });
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
    const totals = rows.reduce((acc, row) => ({
        orders: acc.orders + 1,
        lines: acc.lines + row.lines.length,
        required: (0, money_1.round2)(acc.required + row.totals.required),
        available: (0, money_1.round2)(acc.available + row.totals.available),
        shortage: (0, money_1.round2)(acc.shortage + row.totals.shortage),
    }), { orders: 0, lines: 0, required: 0, available: 0, shortage: 0 });
    return { generatedAt: new Date().toISOString(), rows, totals };
}
//# sourceMappingURL=analytics.service.js.map