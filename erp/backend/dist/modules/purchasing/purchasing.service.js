"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.purchaseOrderInclude = void 0;
exports.createPurchaseOrderTx = createPurchaseOrderTx;
exports.createPurchaseOrder = createPurchaseOrder;
exports.updatePurchaseOrder = updatePurchaseOrder;
exports.setPurchaseOrderStatus = setPurchaseOrderStatus;
exports.receivePurchaseOrder = receivePurchaseOrder;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const sequence_1 = require("../../lib/sequence");
const settings_1 = require("../../lib/settings");
const accounting_service_1 = require("../accounting/accounting.service");
const inventory_service_1 = require("../inventory/inventory.service");
exports.purchaseOrderInclude = {
    supplier: { select: { id: true, name: true, email: true, phone: true } },
    warehouse: { select: { id: true, code: true, name: true } },
    currency: { select: { id: true, code: true, symbol: true } },
    user: { select: { id: true, name: true } },
    lines: {
        include: { product: { select: { id: true, sku: true, name: true, unit: true } } },
    },
};
function mapLines(lines, taxEnabled = true) {
    return lines.map((line) => ({
        productId: line.productId,
        quantity: line.quantity,
        unitCost: line.unitCost,
        taxRate: taxEnabled ? line.taxRate ?? 0 : 0,
    }));
}
function purchaseTotals(lines) {
    return (0, money_1.documentTotals)(lines.map((line) => ({ quantity: line.quantity, unitPrice: line.unitCost, taxRate: line.taxRate })));
}
async function createPurchaseOrderTx(tx, input) {
    if (!input.lines || input.lines.length === 0) {
        throw api_error_1.ApiError.badRequest('A purchase order needs at least one line');
    }
    const settings = await (0, settings_1.getSettings)(tx);
    const lines = mapLines(input.lines, settings.taxEnabled);
    const totals = purchaseTotals(lines);
    const now = new Date();
    const number = await (0, sequence_1.nextNumber)(tx, 'purchaseOrder', settings.purchaseOrderPrefix, now);
    return tx.purchaseOrder.create({
        data: {
            number,
            supplierId: input.supplierId,
            warehouseId: input.warehouseId,
            currencyId: input.currencyId ?? null,
            expectedDate: input.expectedDate ?? null,
            notes: input.notes ?? null,
            userId: input.userId ?? null,
            subtotal: totals.subtotal,
            taxTotal: totals.taxTotal,
            total: totals.total,
            lines: { create: lines },
        },
        include: exports.purchaseOrderInclude,
    });
}
async function createPurchaseOrder(input) {
    return prisma_1.prisma.$transaction((tx) => createPurchaseOrderTx(tx, input));
}
/**
 * Undoes the goods receipt side effects of a purchase order: the received
 * quantity leaves stock again, the supplier balance is reduced by its value
 * and the matching ledger entry is reversed.
 */
async function reverseReceivedGoods(tx, order, lines, userId) {
    const receivedValue = (0, money_1.round2)(lines.reduce((sum, line) => sum + line.receivedQty * Number(line.unitCost), 0));
    if (receivedValue <= 0)
        return;
    const location = await (0, inventory_service_1.resolveLocation)(tx, order.warehouseId);
    for (const line of lines) {
        if (line.receivedQty <= 0)
            continue;
        await (0, inventory_service_1.applyMovement)(tx, {
            type: 'PURCHASE_RETURN',
            productId: line.productId,
            locationId: location.id,
            quantity: -line.receivedQty,
            unitCost: Number(line.unitCost),
            reference: order.number,
            note: `Reversed goods receipt of ${order.number}`,
            userId,
        });
        await tx.purchaseOrderLine.update({
            where: { id: line.id },
            data: { receivedQty: 0 },
        });
    }
    await tx.supplier.update({
        where: { id: order.supplierId },
        data: { balance: { decrement: receivedValue } },
    });
    await (0, accounting_service_1.reverseJournalBySource)(tx, {
        sourceType: 'PURCHASE_ORDER',
        sourceId: order.id,
        reversalSourceType: 'PURCHASE_ORDER_REVERSAL',
        memo: `Goods receipt for ${order.number} reversed`,
        reference: order.number,
        userId,
    });
}
async function updatePurchaseOrder(id, input, options = {}) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const existing = await tx.purchaseOrder.findUnique({
            where: { id },
            include: { lines: true },
        });
        if (!existing)
            throw api_error_1.ApiError.notFound('Purchase order not found');
        if (existing.status === 'CANCELLED') {
            throw api_error_1.ApiError.badRequest('A cancelled purchase order cannot be edited', 'NOT_EDITABLE');
        }
        const editable = existing.status === 'DRAFT' || options.allowPosted === true;
        if (!editable) {
            throw api_error_1.ApiError.badRequest('This purchase order can no longer be edited', 'NOT_EDITABLE');
        }
        // Editing a received order changes what should have come in, so the old
        // receipt is rolled back (stock, supplier balance and ledger) first.
        const hasReceipts = existing.lines.some((line) => line.receivedQty > 0);
        if (hasReceipts) {
            await reverseReceivedGoods(tx, existing, existing.lines.map((line) => ({
                id: line.id,
                productId: line.productId,
                receivedQty: line.receivedQty,
                unitCost: line.unitCost,
            })), options.userId);
        }
        const data = {};
        if (input.expectedDate !== undefined)
            data.expectedDate = input.expectedDate;
        if (input.notes !== undefined)
            data.notes = input.notes;
        if (input.currencyId !== undefined)
            data.currency = input.currencyId ? { connect: { id: input.currencyId } } : { disconnect: true };
        if (input.lines) {
            const settings = await (0, settings_1.getSettings)(tx);
            const lines = mapLines(input.lines, settings.taxEnabled);
            const totals = purchaseTotals(lines);
            await tx.purchaseOrderLine.deleteMany({ where: { purchaseOrderId: id } });
            data.subtotal = totals.subtotal;
            data.taxTotal = totals.taxTotal;
            data.total = totals.total;
            data.lines = { create: lines };
            // A rolled-back receipt returns the order to APPROVED so it can be
            // received again against its new lines.
            if (hasReceipts) {
                data.status = 'APPROVED';
                data.receivedAt = null;
            }
        }
        else if (hasReceipts) {
            data.status = 'APPROVED';
            data.receivedAt = null;
        }
        return tx.purchaseOrder.update({ where: { id }, data, include: exports.purchaseOrderInclude });
    });
}
async function setPurchaseOrderStatus(id, status, options = {}) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const existing = await tx.purchaseOrder.findUnique({
            where: { id },
            include: { lines: true },
        });
        if (!existing)
            throw api_error_1.ApiError.notFound('Purchase order not found');
        if (existing.status === 'CANCELLED') {
            throw api_error_1.ApiError.badRequest('This purchase order is already cancelled', 'NOT_EDITABLE');
        }
        // Cancelling a received order returns the goods, the payable and the
        // ledger entry, so the cancellation leaves no trace on the books.
        if (status === 'CANCELLED') {
            await reverseReceivedGoods(tx, existing, existing.lines.map((line) => ({
                id: line.id,
                productId: line.productId,
                receivedQty: line.receivedQty,
                unitCost: line.unitCost,
            })), options.userId);
        }
        return tx.purchaseOrder.update({
            where: { id },
            data: { status, ...(status === 'CANCELLED' ? { receivedAt: null } : {}) },
            include: exports.purchaseOrderInclude,
        });
    });
}
async function receivePurchaseOrder(id, input) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const order = await tx.purchaseOrder.findUnique({ where: { id }, include: { lines: true } });
        if (!order)
            throw api_error_1.ApiError.notFound('Purchase order not found');
        if (order.status === 'CANCELLED')
            throw api_error_1.ApiError.badRequest('A cancelled purchase order cannot be received');
        if (order.status === 'RECEIVED')
            throw api_error_1.ApiError.badRequest('This purchase order has already been received');
        const location = await (0, inventory_service_1.resolveLocation)(tx, order.warehouseId);
        let receivedValue = 0;
        for (const line of order.lines) {
            const requested = input.lines
                ? input.lines.find((entry) => entry.lineId === line.id)?.quantity ?? 0
                : line.quantity - line.receivedQty;
            const remaining = line.quantity - line.receivedQty;
            const quantity = Math.min(Math.max(0, requested), remaining);
            if (quantity <= 0)
                continue;
            await (0, inventory_service_1.applyMovement)(tx, {
                type: 'PURCHASE',
                productId: line.productId,
                locationId: location.id,
                quantity,
                unitCost: Number(line.unitCost),
                reference: order.number,
                note: `Received against ${order.number}`,
                userId: input.userId,
            });
            // سعر التكلفة يصبح آخر سعر شراء مستلم لهذا المنتج.
            await tx.product.update({
                where: { id: line.productId },
                data: {
                    costPrice: Number(line.unitCost),
                    salePrice: Math.max(Number(line.unitCost), Number((Number(line.unitCost) * 1.03).toFixed(2))),
                },
            });
            await tx.purchaseOrderLine.update({
                where: { id: line.id },
                data: { receivedQty: { increment: quantity } },
            });
            receivedValue += quantity * Number(line.unitCost);
        }
        const refreshed = await tx.purchaseOrderLine.findMany({ where: { purchaseOrderId: id } });
        const fullyReceived = refreshed.length > 0 && refreshed.every((line) => line.receivedQty >= line.quantity);
        const partiallyReceived = refreshed.some((line) => line.receivedQty > 0);
        const updated = await tx.purchaseOrder.update({
            where: { id },
            data: {
                status: fullyReceived ? 'RECEIVED' : partiallyReceived ? 'PARTIALLY_RECEIVED' : order.status,
                receivedAt: fullyReceived ? new Date() : null,
            },
            include: exports.purchaseOrderInclude,
        });
        const value = (0, money_1.round2)(receivedValue);
        if (value > 0) {
            await tx.supplier.update({
                where: { id: order.supplierId },
                data: { balance: { increment: value } },
            });
            await (0, accounting_service_1.postJournal)(tx, {
                memo: `Goods received for ${order.number}`,
                reference: order.number,
                sourceType: 'PURCHASE_ORDER',
                sourceId: order.id,
                userId: input.userId,
                lines: [
                    { accountCode: accounting_service_1.ACCOUNT.INVENTORY, debit: value, description: `Inventory received (${order.number})` },
                    { accountCode: accounting_service_1.ACCOUNT.PAYABLE, credit: value, description: `Payable to supplier` },
                ],
            });
        }
        return updated;
    });
}
//# sourceMappingURL=purchasing.service.js.map