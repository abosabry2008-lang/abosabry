"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildConsolidatedSalesNote = buildConsolidatedSalesNote;
exports.buildProfitBySalesperson = buildProfitBySalesperson;
exports.buildCollectionsBySalesperson = buildCollectionsBySalesperson;
exports.buildSalespersonStatement = buildSalespersonStatement;
exports.buildSalespersonCustomerDebt = buildSalespersonCustomerDebt;
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const reports_service_1 = require("./reports.service");
/** Resolves the representative of an invoice/customer/order combination. */
function resolveRep(customer, order) {
    return customer?.salesperson ?? order?.user ?? null;
}
/**
 * Consolidated sale note: per salesperson, the fulfilled quantities of every
 * product sold in the period, plus the supporting order list.
 */
async function buildConsolidatedSalesNote(fromInput, toInput, salespersonId) {
    const now = new Date();
    const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
    const to = toInput ?? now;
    const where = {
        orderDate: { gte: from, lte: to },
        status: { in: ['PARTIALLY_FULFILLED', 'FULFILLED'] },
    };
    if (salespersonId) {
        where.OR = [
            { customer: { salespersonId } },
            { userId: salespersonId },
        ];
    }
    const orders = await prisma_1.prisma.salesOrder.findMany({
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
    const byRep = new Map();
    for (const order of orders) {
        // Fulfilled quantity is what actually moved; fall back to nothing when the
        // order has no fulfilled line at all.
        const fulfilledLines = order.lines.filter((line) => line.fulfilledQty > 0);
        if (fulfilledLines.length === 0)
            continue;
        const rep = resolveRep(order.customer, order);
        const key = rep?.id ?? '-';
        const row = byRep.get(key) ??
            {
                salespersonId: rep?.id ?? null,
                salesperson: rep?.name ?? null,
                orders: 0,
                quantity: 0,
                net: 0,
                lines: [],
                orderRows: [],
            };
        // Distribute a line's discount proportionally to what was fulfilled.
        const lineMap = new Map();
        let orderQuantity = 0;
        let orderNet = 0;
        for (const line of fulfilledLines) {
            const share = Math.min(1, line.fulfilledQty / (line.quantity || 1));
            const discount = (0, money_1.round2)(Number(line.discount) * share);
            const net = Math.max(0, (0, money_1.round2)(line.fulfilledQty * Number(line.unitPrice) - discount));
            orderQuantity += line.fulfilledQty;
            orderNet += net;
            const entry = lineMap.get(line.productId) ??
                {
                    productId: line.productId,
                    sku: line.product?.sku ?? '',
                    name: line.product?.name ?? '',
                    unit: line.product?.unit ?? '',
                    quantity: 0,
                    net: 0,
                };
            entry.quantity += line.fulfilledQty;
            entry.net = (0, money_1.round2)(entry.net + net);
            lineMap.set(line.productId, entry);
        }
        row.orders += 1;
        row.quantity += orderQuantity;
        row.net = (0, money_1.round2)(row.net + orderNet);
        row.orderRows.push({
            id: order.id,
            number: order.number,
            orderDate: (0, reports_service_1.dayKey)(order.orderDate),
            customer: order.customer?.name ?? null,
            quantity: orderQuantity,
            net: (0, money_1.round2)(orderNet),
        });
        // Merge this order's product lines into the salesperson's consolidated list.
        for (const entry of lineMap.values()) {
            const existing = row.lines.find((line) => line.productId === entry.productId);
            if (existing) {
                existing.quantity += entry.quantity;
                existing.net = (0, money_1.round2)(existing.net + entry.net);
            }
            else {
                row.lines.push({ ...entry });
            }
        }
        byRep.set(key, row);
    }
    // Subtract posted customer returns from each salesperson's net sales.
    const returns = await prisma_1.prisma.returnOrder.findMany({
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
        if (!spId)
            continue;
        const row = byRep.get(spId);
        if (!row)
            continue;
        let returnNet = 0;
        for (const l of ret.lines) {
            const lineNet = (0, money_1.round2)(l.quantity * Number(l.unitPrice));
            returnNet = (0, money_1.round2)(returnNet + lineNet);
            const existing = row.lines.find((x) => x.productId === l.productId);
            if (existing) {
                existing.quantity = Math.max(0, existing.quantity - l.quantity);
                existing.net = (0, money_1.round2)(Math.max(0, existing.net - lineNet));
            }
        }
        row.net = (0, money_1.round2)(Math.max(0, row.net - (returnNet > 0 ? returnNet : Number(ret.total))));
        row.quantity = Math.max(0, row.quantity - ret.lines.reduce((s, l) => s + l.quantity, 0));
    }
    const rows = [...byRep.values()]
        .map((row) => ({
        ...row,
        lines: row.lines.sort((a, b) => b.quantity - a.quantity),
    }))
        .sort((a, b) => (a.salesperson ?? '').localeCompare(b.salesperson ?? ''));
    return {
        from: (0, reports_service_1.dayKey)(from),
        to: (0, reports_service_1.dayKey)(to),
        totals: rows.reduce((acc, row) => ({
            salespeople: acc.salespeople + 1,
            orders: acc.orders + row.orders,
            quantity: acc.quantity + row.quantity,
            net: (0, money_1.round2)(acc.net + row.net),
        }), { salespeople: 0, orders: 0, quantity: 0, net: 0 }),
        rows,
    };
}
/** Revenue (net of discount, excl. tax) minus product cost, per salesperson. */
async function buildProfitBySalesperson(fromInput, toInput, salespersonId) {
    const now = new Date();
    const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
    const to = toInput ?? now;
    const where = {
        status: { notIn: ['DRAFT', 'VOID'] },
        issueDate: { gte: from, lte: to },
    };
    if (salespersonId) {
        where.OR = [
            { customer: { salespersonId } },
            { salesOrder: { userId: salespersonId } },
        ];
    }
    const invoices = await prisma_1.prisma.invoice.findMany({
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
                    discount: true,
                    product: { select: { sku: true, name: true, costPrice: true } },
                },
            },
        },
    });
    const byRep = new Map();
    for (const invoice of invoices) {
        const rep = resolveRep(invoice.customer, invoice.salesOrder);
        const key = rep?.id ?? '-';
        const row = byRep.get(key) ??
            {
                salespersonId: rep?.id ?? null,
                salesperson: rep?.name ?? null,
                orders: 0,
                quantity: 0,
                revenue: 0,
                cost: 0,
                profit: 0,
                margin: 0,
                lines: [],
            };
        row.orders += 1;
        for (const line of invoice.lines) {
            const net = Math.max(0, (0, money_1.round2)(line.quantity * Number(line.unitPrice) - Number(line.discount)));
            const unitCost = line.product ? Number(line.product.costPrice) : 0;
            const lineCost = (0, money_1.round2)(line.quantity * unitCost);
            row.quantity += line.quantity;
            row.revenue = (0, money_1.round2)(row.revenue + net);
            row.cost = (0, money_1.round2)(row.cost + lineCost);
            if (!line.productId || !line.product)
                continue;
            const entry = row.lines.find((item) => item.productId === line.productId);
            if (entry) {
                entry.quantity += line.quantity;
                entry.revenue = (0, money_1.round2)(entry.revenue + net);
                entry.cost = (0, money_1.round2)(entry.cost + lineCost);
                entry.profit = (0, money_1.round2)(entry.revenue - entry.cost);
            }
            else {
                row.lines.push({
                    productId: line.productId,
                    sku: line.product.sku,
                    name: line.product.name,
                    quantity: line.quantity,
                    revenue: net,
                    cost: lineCost,
                    profit: (0, money_1.round2)(net - lineCost),
                });
            }
        }
        byRep.set(key, row);
    }
    const rows = [...byRep.values()].map((row) => {
        const profit = (0, money_1.round2)(row.revenue - row.cost);
        return {
            ...row,
            profit,
            margin: row.revenue > 0 ? (0, money_1.round2)((profit / row.revenue) * 100) : 0,
            lines: row.lines.sort((a, b) => b.profit - a.profit),
        };
    });
    rows.sort((a, b) => b.profit - a.profit);
    const revenue = (0, money_1.round2)(rows.reduce((sum, row) => sum + row.revenue, 0));
    const cost = (0, money_1.round2)(rows.reduce((sum, row) => sum + row.cost, 0));
    const profit = (0, money_1.round2)(revenue - cost);
    return {
        from: (0, reports_service_1.dayKey)(from),
        to: (0, reports_service_1.dayKey)(to),
        totals: {
            salespeople: rows.length,
            revenue,
            cost,
            profit,
            margin: revenue > 0 ? (0, money_1.round2)((profit / revenue) * 100) : 0,
        },
        rows,
    };
}
/** Cash collected from customers by each salesperson within the period. */
async function buildCollectionsBySalesperson(fromInput, toInput, salespersonId) {
    const now = new Date();
    const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
    const to = toInput ?? now;
    const vouchers = await prisma_1.prisma.collectionVoucher.findMany({
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
    const byRep = new Map();
    for (const voucher of vouchers) {
        const rep = voucher.salesperson;
        const key = rep?.id ?? '-';
        const row = byRep.get(key) ??
            {
                salespersonId: rep?.id ?? null,
                salesperson: rep?.name ?? null,
                vouchers: 0,
                amount: 0,
                customers: [],
            };
        row.vouchers += 1;
        // Lines carry the per-customer breakdown; a voucher without lines still
        // counts towards the total (kept on the voucher itself).
        if (voucher.lines.length === 0) {
            row.amount = (0, money_1.round2)(row.amount + Number(voucher.total));
        }
        for (const line of voucher.lines) {
            const amount = Number(line.amount);
            row.amount = (0, money_1.round2)(row.amount + amount);
            const customerId = line.customer?.id ?? null;
            const entry = row.customers.find((item) => item.customerId === customerId);
            if (entry) {
                entry.amount = (0, money_1.round2)(entry.amount + amount);
            }
            else {
                row.customers.push({
                    customerId,
                    customer: line.customer?.name ?? null,
                    amount: (0, money_1.round2)(amount),
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
        from: (0, reports_service_1.dayKey)(from),
        to: (0, reports_service_1.dayKey)(to),
        totals: {
            salespeople: rows.length,
            vouchers: rows.reduce((sum, row) => sum + row.vouchers, 0),
            amount: (0, money_1.round2)(rows.reduce((sum, row) => sum + row.amount, 0)),
        },
        rows,
    };
}
/**
 * A single salesperson's account: what they sold on credit (debit) against what
 * they collected (credit), in date order with a running balance.
 */
async function buildSalespersonStatement(salespersonId, fromInput, toInput) {
    const now = new Date();
    const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
    const to = toInput ?? now;
    const salesperson = await prisma_1.prisma.user.findUnique({
        where: { id: salespersonId },
        select: { id: true, name: true },
    });
    if (!salesperson) {
        // Caller turns this into a 404; a throw keeps the service honest.
        throw new Error('SALESPERSON_NOT_FOUND');
    }
    const [invoices, vouchers] = await Promise.all([
        prisma_1.prisma.invoice.findMany({
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
        prisma_1.prisma.collectionVoucher.findMany({
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
    const movements = [];
    for (const invoice of invoices) {
        const date = (0, reports_service_1.dayKey)(invoice.issueDate);
        movements.push({
            date,
            type: 'SALE',
            reference: invoice.number,
            customer: invoice.customer?.name ?? null,
            debit: (0, money_1.round2)(Number(invoice.total)),
            credit: 0,
            balance: 0,
        });
    }
    for (const voucher of vouchers) {
        const date = (0, reports_service_1.dayKey)(voucher.collectedAt);
        const amount = voucher.lines.length > 0
            ? (0, money_1.round2)(voucher.lines.reduce((sum, line) => sum + Number(line.amount), 0))
            : (0, money_1.round2)(Number(voucher.total));
        const customers = voucher.lines
            .map((line) => line.customer?.name)
            .filter((name) => Boolean(name));
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
    movements.sort((a, b) => a.date.localeCompare(b.date) || a.reference.localeCompare(b.reference));
    // Opening balance = everything that happened before the period start.
    const openingBalance = (0, money_1.round2)(movements
        .filter((row) => row.date < (0, reports_service_1.dayKey)(from))
        .reduce((sum, row) => sum + row.debit - row.credit, 0));
    let running = openingBalance;
    let sales = 0;
    let collections = 0;
    const rows = [];
    for (const movement of movements) {
        if (movement.date < (0, reports_service_1.dayKey)(from))
            continue; // folded into the opening balance
        running = (0, money_1.round2)(running + movement.debit - movement.credit);
        sales = (0, money_1.round2)(sales + movement.debit);
        collections = (0, money_1.round2)(collections + movement.credit);
        rows.push({ ...movement, balance: running });
    }
    // Product mix for the period (reuses the consolidated note logic). Pick the
    // row that actually belongs to this salesperson — a customer may carry a
    // different representative, in which case the note would hold more than one.
    const note = await buildConsolidatedSalesNote(from, to, salespersonId);
    const ownRow = note.rows.find((row) => row.salespersonId === salespersonId) ?? note.rows[0];
    return {
        salesperson,
        from: (0, reports_service_1.dayKey)(from),
        to: (0, reports_service_1.dayKey)(to),
        openingBalance,
        totals: { sales, collections, closingBalance: running },
        rows,
        byProduct: ownRow?.lines ?? [],
    };
}
/**
 * One row per customer handled by a salesperson, in the classic ledger shape:
 * `# | customer | previous | debit | credit | balance`.
 *
 * Sales come from issued invoices, collections from non-cancelled vouchers,
 * and the "previous" column is whatever balance existed before the period.
 */
async function buildSalespersonCustomerDebt(salespersonId, fromInput, toInput) {
    const now = new Date();
    const from = fromInput ?? new Date(now.getFullYear(), 0, 1);
    const to = toInput ?? now;
    const fromKey = (0, reports_service_1.dayKey)(from);
    const toKey = (0, reports_service_1.dayKey)(to);
    const salesperson = await prisma_1.prisma.user.findUnique({
        where: { id: salespersonId },
        select: { id: true, name: true },
    });
    if (!salesperson)
        throw new Error('SALESPERSON_NOT_FOUND');
    const [invoices, voucherLines] = await Promise.all([
        prisma_1.prisma.invoice.findMany({
            where: {
                status: { notIn: ['DRAFT', 'VOID'] },
                issueDate: { lte: to },
                OR: [
                    { customer: { salespersonId } },
                    { customer: { salespersonId: null }, salesOrder: { userId: salespersonId } },
                    { salesOrder: { userId: salespersonId } },
                ],
            },
            select: {
                issueDate: true,
                total: true,
                amountPaid: true,
                customer: { select: { id: true, name: true, phone: true } },
            },
        }),
        prisma_1.prisma.collectionLine.findMany({
            where: {
                collection: { salespersonId, cancelledAt: null, collectedAt: { lte: to } },
            },
            select: {
                amount: true,
                customer: { select: { id: true, name: true, phone: true } },
                collection: { select: { collectedAt: true } },
            },
        }),
    ]);
    const map = new Map();
    const bucketFor = (id, name, phone) => {
        const key = id ?? 'walk-in';
        const existing = map.get(key);
        if (existing)
            return existing;
        const created = {
            customerId: key,
            customer: name ?? 'Walk-in',
            phone,
            previous: 0,
            debit: 0,
            credit: 0,
        };
        map.set(key, created);
        return created;
    };
    for (const invoice of invoices) {
        const bucket = bucketFor(invoice.customer?.id ?? null, invoice.customer?.name ?? null, invoice.customer?.phone ?? null);
        const key = (0, reports_service_1.dayKey)(invoice.issueDate);
        const amount = Number(invoice.total);
        // Anything issued before the period (and unpaid) rolls into "previous".
        const settled = Number(invoice.amountPaid);
        if (key < fromKey) {
            bucket.previous = (0, money_1.round2)(bucket.previous + (amount - settled));
        }
        else {
            bucket.debit = (0, money_1.round2)(bucket.debit + amount);
        }
    }
    for (const line of voucherLines) {
        const bucket = bucketFor(line.customer?.id ?? null, line.customer?.name ?? null, line.customer?.phone ?? null);
        const key = (0, reports_service_1.dayKey)(line.collection.collectedAt);
        const amount = Number(line.amount);
        if (key < fromKey) {
            bucket.previous = (0, money_1.round2)(bucket.previous - amount);
        }
        else {
            bucket.credit = (0, money_1.round2)(bucket.credit + amount);
        }
    }
    const rows = [...map.values()]
        .map((bucket) => ({
        ...bucket,
        balance: (0, money_1.round2)(bucket.previous + bucket.debit - bucket.credit),
    }))
        .filter((row) => row.previous !== 0 || row.debit !== 0 || row.credit !== 0)
        .sort((a, b) => b.balance - a.balance || a.customer.localeCompare(b.customer));
    const totals = rows.reduce((acc, row) => ({
        previous: (0, money_1.round2)(acc.previous + row.previous),
        debit: (0, money_1.round2)(acc.debit + row.debit),
        credit: (0, money_1.round2)(acc.credit + row.credit),
        balance: (0, money_1.round2)(acc.balance + row.balance),
    }), { previous: 0, debit: 0, credit: 0, balance: 0 });
    return { salesperson, from: fromKey, to: toKey, rows, totals };
}
//# sourceMappingURL=salespeople.service.js.map