"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.returnOrderInclude = void 0;
exports.createReturnOrderTx = createReturnOrderTx;
exports.createReturnOrder = createReturnOrder;
exports.updateReturnOrderTx = updateReturnOrderTx;
exports.updateReturnOrder = updateReturnOrder;
exports.postReturnOrderTx = postReturnOrderTx;
exports.postReturnOrder = postReturnOrder;
exports.cancelReturnOrder = cancelReturnOrder;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const sequence_1 = require("../../lib/sequence");
const settings_1 = require("../../lib/settings");
const accounting_service_1 = require("../accounting/accounting.service");
const inventory_service_1 = require("../inventory/inventory.service");
exports.returnOrderInclude = {
    customer: { select: { id: true, name: true, phone: true } },
    supplier: { select: { id: true, name: true, phone: true } },
    warehouse: { select: { id: true, code: true, name: true } },
    user: { select: { id: true, name: true } },
    lines: {
        include: { product: { select: { id: true, sku: true, name: true, unit: true } } },
    },
};
async function createReturnOrderTx(tx, input) {
    if (!input.lines || input.lines.length === 0) {
        throw api_error_1.ApiError.badRequest('A return order needs at least one line');
    }
    if (input.type === 'CUSTOMER_RETURN' && !input.customerId) {
        throw api_error_1.ApiError.badRequest('A customer return needs a customer', 'CUSTOMER_REQUIRED');
    }
    if (input.type === 'SUPPLIER_RETURN' && !input.supplierId) {
        throw api_error_1.ApiError.badRequest('A supplier return needs a supplier', 'SUPPLIER_REQUIRED');
    }
    const settings = await (0, settings_1.getSettings)(tx);
    const taxEnabled = settings.taxEnabled;
    const products = await tx.product.findMany({
        where: { id: { in: input.lines.map((line) => line.productId) } },
    });
    const byId = new Map(products.map((product) => [product.id, product]));
    const lines = input.lines.map((line) => {
        const product = byId.get(line.productId);
        if (!product)
            throw api_error_1.ApiError.badRequest(`Product ${line.productId} not found`, 'PRODUCT_NOT_FOUND');
        return {
            productId: line.productId,
            quantity: line.quantity,
            // سعر المرتجع الافتراضي = سعر البيع للعميل، وسعر البيع أو التكلفة للمورد.
            unitPrice: line.unitPrice ??
                (input.type === 'CUSTOMER_RETURN' ? Number(product.salePrice) : Number(product.costPrice)),
            unitCost: Number(product.costPrice),
            taxRate: taxEnabled ? line.taxRate ?? 0 : 0,
        };
    });
    const totals = (0, money_1.documentTotals)(lines.map((line) => ({
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        taxRate: line.taxRate,
    })));
    const number = await (0, sequence_1.nextNumber)(tx, 'returnOrder', 'RET');
    return tx.returnOrder.create({
        data: {
            number,
            type: input.type,
            customerId: input.type === 'CUSTOMER_RETURN' ? input.customerId ?? null : null,
            supplierId: input.type === 'SUPPLIER_RETURN' ? input.supplierId ?? null : null,
            warehouseId: input.warehouseId,
            notes: input.notes ?? null,
            userId: input.userId ?? null,
            subtotal: totals.subtotal,
            taxTotal: totals.taxTotal,
            total: totals.total,
            lines: { create: lines },
        },
        include: exports.returnOrderInclude,
    });
}
async function createReturnOrder(input) {
    return prisma_1.prisma.$transaction((tx) => createReturnOrderTx(tx, input));
}
async function updateReturnOrderTx(tx, id, input, options = {}) {
    const existing = await tx.returnOrder.findUnique({ where: { id }, include: exports.returnOrderInclude });
    if (!existing)
        throw api_error_1.ApiError.notFound('Return order not found');
    if (existing.status === 'CANCELLED') {
        throw api_error_1.ApiError.badRequest('A cancelled return order cannot be edited', 'NOT_EDITABLE');
    }
    // Only admins (via `allowPosted`) may edit an already-posted return order.
    const editable = existing.status === 'DRAFT' ||
        (existing.status === 'POSTED' && options.allowPosted === true);
    if (!editable) {
        throw api_error_1.ApiError.badRequest('Only draft return orders can be edited', 'NOT_EDITABLE');
    }
    const data = {};
    if (input.notes !== undefined)
        data.notes = input.notes;
    let newTotals = null;
    let newLines = null;
    if (input.lines && input.lines.length > 0) {
        const settings = await (0, settings_1.getSettings)(tx);
        const taxEnabled = settings.taxEnabled;
        const products = await tx.product.findMany({
            where: { id: { in: input.lines.map((line) => line.productId) } },
        });
        const byId = new Map(products.map((product) => [product.id, product]));
        newLines = input.lines.map((line) => {
            const product = byId.get(line.productId);
            if (!product)
                throw api_error_1.ApiError.badRequest(`Product ${line.productId} not found`, 'PRODUCT_NOT_FOUND');
            return {
                productId: line.productId,
                quantity: line.quantity,
                unitPrice: line.unitPrice ??
                    (existing.type === 'CUSTOMER_RETURN' ? Number(product.salePrice) : Number(product.costPrice)),
                unitCost: Number(product.costPrice),
                taxRate: taxEnabled ? line.taxRate ?? 0 : 0,
            };
        });
        newTotals = (0, money_1.documentTotals)(newLines.map((line) => ({
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            taxRate: line.taxRate,
        })));
    }
    // If posted, reverse effects first (stock, partner balance, journal)
    if (existing.status === 'POSTED') {
        const location = await (0, inventory_service_1.resolveLocation)(tx, existing.warehouseId);
        for (const line of existing.lines) {
            const quantity = Math.max(0, line.quantity);
            if (quantity <= 0)
                continue;
            const unitCost = Number(line.unitCost);
            if (existing.type === 'CUSTOMER_RETURN') {
                await (0, inventory_service_1.drawFromWarehouse)(tx, {
                    warehouseId: existing.warehouseId,
                    productId: line.productId,
                    quantity,
                    type: 'SALE_RETURN',
                    unitCost,
                    reference: existing.number,
                    note: `Customer return ${existing.number} edited`,
                });
            }
            else {
                await (0, inventory_service_1.applyMovement)(tx, {
                    type: 'PURCHASE_RETURN',
                    productId: line.productId,
                    locationId: location.id,
                    quantity,
                    unitCost,
                    reference: existing.number,
                    note: `Supplier return ${existing.number} edited`,
                });
            }
        }
        const value = (0, money_1.round2)(Number(existing.total));
        if (existing.type === 'CUSTOMER_RETURN') {
            if (existing.customerId) {
                await tx.customer.update({ where: { id: existing.customerId }, data: { balance: { increment: value } } });
            }
        }
        else {
            if (existing.supplierId) {
                await tx.supplier.update({ where: { id: existing.supplierId }, data: { balance: { increment: value } } });
            }
        }
        await (0, accounting_service_1.reverseJournalBySource)(tx, {
            sourceType: 'RETURN_ORDER',
            sourceId: existing.id,
            reversalSourceType: 'RETURN_ORDER_EDIT',
            memo: `Return order ${existing.number} edited`,
            reference: existing.number,
        });
    }
    if (newTotals && newLines) {
        await tx.returnOrderLine.deleteMany({ where: { returnOrderId: id } });
        data.subtotal = newTotals.subtotal;
        data.taxTotal = newTotals.taxTotal;
        data.total = newTotals.total;
        data.lines = { create: newLines };
    }
    const updated = await tx.returnOrder.update({ where: { id }, data, include: exports.returnOrderInclude });
    // If it was posted, re-post with new data
    if (existing.status === 'POSTED') {
        return postReturnOrderTx(tx, updated.id, undefined);
    }
    return updated;
}
async function updateReturnOrder(id, input, options = {}) {
    return prisma_1.prisma.$transaction((tx) => updateReturnOrderTx(tx, id, input, options));
}
/**
 * Posts a return order: moves the stock back (customer return) or out
 * (supplier return), adjusts the partner balance and records the journal.
 */
async function postReturnOrderTx(tx, id, userId) {
    const order = await tx.returnOrder.findUnique({ where: { id }, include: { lines: true } });
    if (!order)
        throw api_error_1.ApiError.notFound('Return order not found');
    if (order.status === 'POSTED')
        throw api_error_1.ApiError.badRequest('This return order has already been posted');
    if (order.status === 'CANCELLED')
        throw api_error_1.ApiError.badRequest('A cancelled return order cannot be posted');
    const location = await (0, inventory_service_1.resolveLocation)(tx, order.warehouseId);
    let costTotal = 0;
    for (const line of order.lines) {
        const quantity = Math.max(0, line.quantity);
        if (quantity <= 0)
            continue;
        const unitCost = Number(line.unitCost);
        costTotal += quantity * unitCost;
        if (order.type === 'CUSTOMER_RETURN') {
            // المرتجع من العميل يرجع البضاعة للمخزون.
            await (0, inventory_service_1.applyMovement)(tx, {
                type: 'SALE_RETURN',
                productId: line.productId,
                locationId: location.id,
                quantity,
                unitCost,
                reference: order.number,
                note: `Customer return ${order.number}`,
                userId,
            });
        }
        else {
            // المرتجع للمورد يخرج البضاعة من المخزون.
            await (0, inventory_service_1.drawFromWarehouse)(tx, {
                warehouseId: order.warehouseId,
                productId: line.productId,
                quantity,
                type: 'PURCHASE_RETURN',
                unitCost,
                reference: order.number,
                note: `Supplier return ${order.number}`,
                userId,
            });
        }
    }
    const value = (0, money_1.round2)(Number(order.total));
    const cost = (0, money_1.round2)(costTotal);
    if (order.type === 'CUSTOMER_RETURN') {
        if (order.customerId) {
            await tx.customer.update({
                where: { id: order.customerId },
                data: { balance: { decrement: value } },
            });
        }
        await (0, accounting_service_1.postJournal)(tx, {
            memo: `Customer return ${order.number}`,
            reference: order.number,
            sourceType: 'RETURN_ORDER',
            sourceId: order.id,
            userId,
            lines: [
                { accountCode: accounting_service_1.ACCOUNT.REVENUE, debit: (0, money_1.round2)(Number(order.subtotal)), description: `Sales return ${order.number}` },
                { accountCode: accounting_service_1.ACCOUNT.TAX_PAYABLE, debit: (0, money_1.round2)(Number(order.taxTotal)), description: `Reversed tax ${order.number}` },
                { accountCode: order.customerId ? accounting_service_1.ACCOUNT.RECEIVABLE : accounting_service_1.ACCOUNT.CASH, credit: value, description: `Customer refund ${order.number}` },
                { accountCode: accounting_service_1.ACCOUNT.INVENTORY, debit: cost, description: `Returned goods ${order.number}` },
                { accountCode: accounting_service_1.ACCOUNT.COGS, credit: cost, description: `Reversed cost of sales ${order.number}` },
            ],
        });
    }
    else {
        if (order.supplierId) {
            await tx.supplier.update({
                where: { id: order.supplierId },
                data: { balance: { decrement: value } },
            });
        }
        await (0, accounting_service_1.postJournal)(tx, {
            memo: `Supplier return ${order.number}`,
            reference: order.number,
            sourceType: 'RETURN_ORDER',
            sourceId: order.id,
            userId,
            lines: [
                { accountCode: accounting_service_1.ACCOUNT.PAYABLE, debit: value, description: `Return to supplier ${order.number}` },
                { accountCode: accounting_service_1.ACCOUNT.INVENTORY, credit: cost, description: `Inventory returned ${order.number}` },
            ],
        });
    }
    return tx.returnOrder.update({
        where: { id },
        data: { status: 'POSTED', returnDate: new Date() },
        include: exports.returnOrderInclude,
    });
}
async function postReturnOrder(id, userId) {
    return prisma_1.prisma.$transaction((tx) => postReturnOrderTx(tx, id, userId));
}
async function cancelReturnOrder(id, options = {}) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const order = await tx.returnOrder.findUnique({ where: { id }, include: { lines: true } });
        if (!order)
            throw api_error_1.ApiError.notFound('Return order not found');
        if (order.status === 'CANCELLED')
            throw api_error_1.ApiError.badRequest('This return order is already cancelled');
        if (order.status === 'POSTED' && options.allowPosted !== true) {
            throw api_error_1.ApiError.badRequest('A posted return order cannot be cancelled', 'NOT_CANCELLABLE');
        }
        // If posted, reverse all effects: stock, partner balance, journal.
        if (order.status === 'POSTED') {
            const location = await (0, inventory_service_1.resolveLocation)(tx, order.warehouseId);
            for (const line of order.lines) {
                const quantity = Math.max(0, line.quantity);
                if (quantity <= 0)
                    continue;
                const unitCost = Number(line.unitCost);
                if (order.type === 'CUSTOMER_RETURN') {
                    // Customer return added stock; reverse by removing it.
                    await (0, inventory_service_1.drawFromWarehouse)(tx, {
                        warehouseId: order.warehouseId,
                        productId: line.productId,
                        quantity,
                        type: 'SALE_RETURN',
                        unitCost,
                        reference: order.number,
                        note: `Customer return ${order.number} cancelled`,
                    });
                }
                else {
                    // Supplier return removed stock; reverse by adding it back.
                    await (0, inventory_service_1.applyMovement)(tx, {
                        type: 'PURCHASE_RETURN',
                        productId: line.productId,
                        locationId: location.id,
                        quantity,
                        unitCost,
                        reference: order.number,
                        note: `Supplier return ${order.number} cancelled`,
                    });
                }
            }
            const value = (0, money_1.round2)(Number(order.total));
            if (order.type === 'CUSTOMER_RETURN') {
                if (order.customerId) {
                    await tx.customer.update({
                        where: { id: order.customerId },
                        data: { balance: { increment: value } },
                    });
                }
            }
            else {
                if (order.supplierId) {
                    await tx.supplier.update({
                        where: { id: order.supplierId },
                        data: { balance: { increment: value } },
                    });
                }
            }
            await (0, accounting_service_1.reverseJournalBySource)(tx, {
                sourceType: 'RETURN_ORDER',
                sourceId: order.id,
                reversalSourceType: 'RETURN_ORDER_CANCEL',
                memo: `Return order ${order.number} cancelled`,
                reference: order.number,
            });
        }
        return tx.returnOrder.update({
            where: { id },
            data: { status: 'CANCELLED' },
            include: exports.returnOrderInclude,
        });
    });
}
//# sourceMappingURL=returns.service.js.map