"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.salesOrderInclude = void 0;
exports.createSalesOrderTx = createSalesOrderTx;
exports.confirmSalesOrderTx = confirmSalesOrderTx;
exports.checkSalesOrderAvailability = checkSalesOrderAvailability;
exports.fulfillSalesOrderTx = fulfillSalesOrderTx;
exports.registerSaleTx = registerSaleTx;
exports.createSalesOrder = createSalesOrder;
exports.updateSalesOrder = updateSalesOrder;
exports.confirmSalesOrder = confirmSalesOrder;
exports.fulfillSalesOrder = fulfillSalesOrder;
exports.cancelSalesOrder = cancelSalesOrder;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const sequence_1 = require("../../lib/sequence");
const settings_1 = require("../../lib/settings");
const inventory_service_1 = require("../inventory/inventory.service");
const inventory_service_2 = require("../inventory/inventory.service");
const accounting_service_1 = require("../accounting/accounting.service");
exports.salesOrderInclude = {
    customer: { select: { id: true, name: true, email: true, phone: true } },
    warehouse: { select: { id: true, code: true, name: true } },
    currency: { select: { id: true, code: true, symbol: true } },
    user: { select: { id: true, name: true } },
    lines: {
        include: {
            product: {
                select: {
                    id: true,
                    sku: true,
                    name: true,
                    unit: true,
                    boxesPerCarton: true,
                    boxPrice: true,
                    cartonPrice: true,
                    salePrice: true,
                    costPrice: true,
                },
            },
        },
    },
};
function resolvePack(product, sellUnit) {
    const boxesPerCarton = product.boxesPerCarton ?? 0;
    if (sellUnit === 'box' && boxesPerCarton > 0) {
        const boxPrice = product.boxPrice != null ? Number(product.boxPrice) : Number(product.salePrice);
        return { baseQty: boxesPerCarton > 0 ? 1 : 1, qtyInBase: 1, unitPrice: boxPrice, sellUnit: 'box' };
    }
    if (sellUnit === 'carton' && boxesPerCarton > 0) {
        const cartonPrice = product.cartonPrice != null ? Number(product.cartonPrice) : boxesPerCarton * Number(product.salePrice);
        return { baseQty: boxesPerCarton, qtyInBase: boxesPerCarton, unitPrice: cartonPrice, sellUnit: 'carton' };
    }
    return { baseQty: 1, qtyInBase: 1, unitPrice: Number(product.salePrice), sellUnit: 'unit' };
}
async function resolveLines(tx, lines, taxEnabled = true) {
    if (!lines || lines.length === 0)
        throw api_error_1.ApiError.badRequest('An order needs at least one line');
    const products = await tx.product.findMany({
        where: { id: { in: lines.map((line) => line.productId) } },
    });
    const byId = new Map(products.map((product) => [product.id, product]));
    return lines.map((line) => {
        const product = byId.get(line.productId);
        if (!product)
            throw api_error_1.ApiError.badRequest(`Product ${line.productId} not found`, 'PRODUCT_NOT_FOUND');
        const sellUnit = line.sellUnit === 'box' || line.sellUnit === 'carton' ? line.sellUnit : 'unit';
        const pack = resolvePack(product, sellUnit);
        const unitPrice = line.unitPrice ?? pack.unitPrice;
        // لا يُسمح بالبيع بسعر أقل من التكلفة.
        const costPrice = Number(product.costPrice);
        if (unitPrice < costPrice) {
            throw api_error_1.ApiError.badRequest(`Selling price for "${product.name}" (${unitPrice}) is below its cost price (${costPrice})`, 'BELOW_COST', { productId: product.id, unitPrice, costPrice });
        }
        const quantity = sellUnit === 'carton' && (product.boxesPerCarton ?? 0) > 0 ? line.quantity * (product.boxesPerCarton ?? 1) : sellUnit === 'box' ? line.quantity : line.quantity;
        // quantity stored in base units for inventory
        const baseQuantity = sellUnit === 'carton' && (product.boxesPerCarton ?? 0) > 0 ? line.quantity * (product.boxesPerCarton ?? 1) : line.quantity;
        return {
            productId: line.productId,
            quantity: baseQuantity,
            unitPrice,
            discount: line.discount ?? 0,
            taxRate: taxEnabled ? line.taxRate ?? Number(product.taxRate) : 0,
            sellUnit,
        };
    });
}
function totalsOf(lines) {
    return (0, money_1.documentTotals)(lines.map((line) => ({
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        discount: line.discount,
        taxRate: line.taxRate,
    })));
}
async function createSalesOrderTx(tx, input) {
    const settings = await (0, settings_1.getSettings)(tx);
    const lines = await resolveLines(tx, input.lines, settings.taxEnabled);
    const totals = totalsOf(lines);
    const now = new Date();
    const number = await (0, sequence_1.nextNumber)(tx, 'salesOrder', settings.salesOrderPrefix, now);
    return tx.salesOrder.create({
        data: {
            number,
            customerId: input.customerId ?? null,
            warehouseId: input.warehouseId,
            currencyId: input.currencyId ?? null,
            channel: input.channel ?? 'MANUAL',
            status: 'DRAFT',
            notes: input.notes ?? null,
            userId: input.userId ?? null,
            subtotal: totals.subtotal,
            discountTotal: totals.discountTotal,
            taxTotal: totals.taxTotal,
            total: totals.total,
            lines: {
                create: lines.map((line) => ({
                    productId: line.productId,
                    quantity: line.quantity,
                    unitPrice: line.unitPrice,
                    discount: line.discount,
                    taxRate: line.taxRate,
                    sellUnit: line.sellUnit,
                })),
            },
        },
        include: exports.salesOrderInclude,
    });
}
async function confirmSalesOrderTx(tx, id) {
    const order = await tx.salesOrder.findUnique({ where: { id } });
    if (!order)
        throw api_error_1.ApiError.notFound('Sales order not found');
    if (order.status !== 'DRAFT') {
        throw api_error_1.ApiError.badRequest(`A ${order.status.toLowerCase()} order cannot be confirmed`, 'NOT_CONFIRMABLE');
    }
    return tx.salesOrder.update({ where: { id }, data: { status: 'CONFIRMED' }, include: exports.salesOrderInclude });
}
/** Available stock of a product across the active locations of a warehouse. */
async function availableInWarehouse(tx, warehouseId, productId) {
    const locations = await tx.location.findMany({
        where: { warehouseId, active: true },
        select: { id: true },
    });
    if (locations.length === 0)
        return 0;
    const levels = await tx.stockLevel.findMany({
        where: {
            productId,
            locationId: { in: locations.map((location) => location.id) },
            quantity: { gt: 0 },
        },
        select: { quantity: true },
    });
    return levels.reduce((sum, level) => sum + level.quantity, 0);
}
/**
 * Compares every open line of an order with the stock on hand, so the UI can
 * warn before fulfilling that some items are missing.
 */
async function checkSalesOrderAvailability(id) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const order = await tx.salesOrder.findUnique({
            where: { id },
            include: {
                lines: {
                    include: {
                        product: { select: { id: true, name: true, sku: true } },
                    },
                },
            },
        });
        if (!order)
            throw api_error_1.ApiError.notFound('Sales order not found');
        const lines = [];
        for (const line of order.lines) {
            const requested = line.quantity - line.fulfilledQty;
            if (requested <= 0)
                continue;
            const available = await availableInWarehouse(tx, order.warehouseId, line.productId);
            lines.push({
                lineId: line.id,
                productId: line.productId,
                productName: line.product.name,
                sku: line.product.sku,
                requested,
                available,
                shortfall: Math.max(0, requested - available),
            });
        }
        const totals = lines.reduce((acc, line) => ({
            requested: acc.requested + line.requested,
            available: acc.available + line.available,
            shortfall: acc.shortfall + line.shortfall,
        }), { requested: 0, available: 0, shortfall: 0 });
        return {
            orderId: order.id,
            orderNumber: order.number,
            warehouseId: order.warehouseId,
            canFulfillEverything: totals.shortfall === 0,
            lines,
            totals,
        };
    });
}
async function fulfillSalesOrderTx(tx, id, input) {
    const order = await tx.salesOrder.findUnique({
        where: { id },
        include: { lines: { include: { product: { select: { name: true } } } } },
    });
    if (!order)
        throw api_error_1.ApiError.notFound('Sales order not found');
    if (order.status === 'CANCELLED')
        throw api_error_1.ApiError.badRequest('A cancelled order cannot be fulfilled');
    if (order.status === 'FULFILLED')
        throw api_error_1.ApiError.badRequest('This order has already been fulfilled');
    for (const line of order.lines) {
        const requested = input.lines
            ? input.lines.find((entry) => entry.lineId === line.id)?.quantity ?? 0
            : line.quantity - line.fulfilledQty;
        const remaining = line.quantity - line.fulfilledQty;
        let quantity = Math.min(Math.max(0, requested), remaining);
        if (quantity <= 0)
            continue;
        // When the operator chose to skip missing items, cap the draw at what is
        // actually on the shelf instead of failing the whole fulfilment.
        if (input.onlyAvailable) {
            const available = await availableInWarehouse(tx, order.warehouseId, line.productId);
            quantity = Math.min(quantity, available);
            if (quantity <= 0)
                continue;
        }
        await (0, inventory_service_2.drawFromWarehouse)(tx, {
            warehouseId: order.warehouseId,
            productId: line.productId,
            quantity,
            type: 'SALE',
            unitCost: Number(line.unitPrice),
            reference: order.number,
            userId: input.userId,
        });
        await tx.salesOrderLine.update({
            where: { id: line.id },
            data: { fulfilledQty: { increment: quantity } },
        });
    }
    const refreshed = await tx.salesOrderLine.findMany({ where: { salesOrderId: id } });
    const fullyFulfilled = refreshed.length > 0 && refreshed.every((line) => line.fulfilledQty >= line.quantity);
    const partiallyFulfilled = refreshed.some((line) => line.fulfilledQty > 0);
    return tx.salesOrder.update({
        where: { id },
        data: {
            status: fullyFulfilled ? 'FULFILLED' : partiallyFulfilled ? 'PARTIALLY_FULFILLED' : order.status,
            fulfilledAt: fullyFulfilled ? new Date() : null,
        },
        include: exports.salesOrderInclude,
    });
}
async function restoreFulfilledStock(tx, order, lines, userId) {
    const pending = lines.filter((line) => line.fulfilledQty > 0);
    if (pending.length === 0)
        return;
    const location = await (0, inventory_service_1.resolveLocation)(tx, order.warehouseId);
    for (const line of pending) {
        await (0, inventory_service_1.applyMovement)(tx, {
            type: 'SALE_RETURN',
            productId: line.productId,
            locationId: location.id,
            quantity: line.fulfilledQty,
            unitCost: Number(line.unitPrice),
            reference: order.number,
            note: `Reversed fulfilment of ${order.number}`,
            userId,
        });
        await tx.salesOrderLine.update({
            where: { id: line.id },
            data: { fulfilledQty: 0 },
        });
    }
}
/** Creates, confirms and fulfils an order in one step (used by the POS). */
async function registerSaleTx(tx, input, userId) {
    const order = await createSalesOrderTx(tx, { ...input, userId });
    await confirmSalesOrderTx(tx, order.id);
    return fulfillSalesOrderTx(tx, order.id, { userId });
}
// ---------------------------------------------------------------------------
// Transaction-wrapping entry points used by the routes
// ---------------------------------------------------------------------------
async function createSalesOrder(input) {
    return prisma_1.prisma.$transaction((tx) => createSalesOrderTx(tx, input));
}
async function updateSalesOrder(id, input, options = {}) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const existing = await tx.salesOrder.findUnique({
            where: { id },
            include: { lines: true },
        });
        if (!existing)
            throw api_error_1.ApiError.notFound('Sales order not found');
        if (existing.status === 'CANCELLED') {
            throw api_error_1.ApiError.badRequest('A cancelled sales order cannot be edited', 'NOT_EDITABLE');
        }
        const editable = existing.status === 'DRAFT' || options.allowPosted === true;
        if (!editable) {
            throw api_error_1.ApiError.badRequest('Only draft sales orders can be edited', 'NOT_EDITABLE');
        }
        // Editing a fulfilled order changes what should have left the warehouse,
        // so the old fulfilment is rolled back before the new lines are applied.
        const hadFulfilment = existing.lines.some((line) => line.fulfilledQty > 0);
        if (hadFulfilment) {
            if (existing.status === 'FULFILLED' || existing.status === 'PARTIALLY_FULFILLED') {
                await restoreFulfilledStock(tx, existing, existing.lines.map((line) => ({
                    id: line.id,
                    productId: line.productId,
                    fulfilledQty: line.fulfilledQty,
                    unitPrice: line.unitPrice,
                })), options.userId);
            }
        }
        const data = {};
        if (input.customerId !== undefined) {
            data.customer = input.customerId ? { connect: { id: input.customerId } } : { disconnect: true };
        }
        if (input.currencyId !== undefined) {
            data.currency = input.currencyId ? { connect: { id: input.currencyId } } : { disconnect: true };
        }
        if (input.notes !== undefined)
            data.notes = input.notes;
        if (input.lines) {
            const settings = await (0, settings_1.getSettings)(tx);
            const lines = await resolveLines(tx, input.lines, settings.taxEnabled);
            const totals = totalsOf(lines);
            await tx.salesOrderLine.deleteMany({ where: { salesOrderId: id } });
            data.subtotal = totals.subtotal;
            data.discountTotal = totals.discountTotal;
            data.taxTotal = totals.taxTotal;
            data.total = totals.total;
            data.lines = {
                create: lines.map((line) => ({
                    productId: line.productId,
                    quantity: line.quantity,
                    unitPrice: line.unitPrice,
                    discount: line.discount,
                    taxRate: line.taxRate,
                    sellUnit: line.sellUnit,
                })),
            };
            // Changing the lines of a fulfilment resets it: the order goes back to
            // CONFIRMED and the stock is re-drawn from the new quantities below.
            if (existing.status === 'FULFILLED' || existing.status === 'PARTIALLY_FULFILLED') {
                data.status = 'CONFIRMED';
                data.fulfilledAt = null;
            }
        }
        const updated = await tx.salesOrder.update({ where: { id }, data, include: exports.salesOrderInclude });
        // Re-draw the stock for an order that was fulfilled before the edit.
        if (hadFulfilment && input.lines && updated.status === 'CONFIRMED') {
            return fulfillSalesOrderTx(tx, id, { userId: options.userId });
        }
        return updated;
    });
}
async function confirmSalesOrder(id) {
    return prisma_1.prisma.$transaction((tx) => confirmSalesOrderTx(tx, id));
}
async function fulfillSalesOrder(id, input) {
    return prisma_1.prisma.$transaction((tx) => fulfillSalesOrderTx(tx, id, input));
}
/**
 * Cancels a sales order — including one that was already fulfilled.
 *
 * Cancelling an executed order reverses everything it caused: the stock that
 * left the warehouse comes back, and any ledger entry posted for the order is
 * reversed, so inventory and accounting no longer reflect a document we are
 * pulling back.
 */
async function cancelSalesOrder(id, options = {}) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const order = await tx.salesOrder.findUnique({
            where: { id },
            include: { lines: true, invoices: { select: { id: true, number: true, status: true } } },
        });
        if (!order)
            throw api_error_1.ApiError.notFound('Sales order not found');
        if (order.status === 'CANCELLED') {
            throw api_error_1.ApiError.badRequest('This order is already cancelled');
        }
        // Live invoices must be voided first, otherwise revenue would stay on the
        // books for an order that no longer exists.
        const liveInvoices = order.invoices.filter((invoice) => invoice.status !== 'VOID');
        if (liveInvoices.length > 0) {
            throw api_error_1.ApiError.conflict(`This order has an active invoice (${liveInvoices.map((i) => i.number).join(', ')}) — void it first`, 'HAS_INVOICES', { invoices: liveInvoices.map((invoice) => invoice.number) });
        }
        // Put back whatever was fulfilled.
        await restoreFulfilledStock(tx, order, order.lines.map((line) => ({
            id: line.id,
            productId: line.productId,
            fulfilledQty: line.fulfilledQty,
            unitPrice: line.unitPrice,
        })), options.userId);
        // Reverse any ledger entry posted for the order itself.
        await (0, accounting_service_1.reverseJournalBySource)(tx, {
            sourceType: 'SALES_ORDER',
            sourceId: order.id,
            reversalSourceType: 'SALES_ORDER_CANCEL',
            memo: `Sales order ${order.number} cancelled`,
            reference: order.number,
            userId: options.userId,
        });
        return tx.salesOrder.update({
            where: { id },
            data: { status: 'CANCELLED', fulfilledAt: null },
            include: exports.salesOrderInclude,
        });
    });
}
//# sourceMappingURL=sales.service.js.map