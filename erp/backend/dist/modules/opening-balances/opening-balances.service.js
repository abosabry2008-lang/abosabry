"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.openingBalanceInclude = void 0;
exports.createOpeningBalanceTx = createOpeningBalanceTx;
exports.createOpeningBalance = createOpeningBalance;
exports.cancelOpeningBalance = cancelOpeningBalance;
exports.listOpeningBalances = listOpeningBalances;
const api_error_1 = require("../../lib/api-error");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const sequence_1 = require("../../lib/sequence");
const settings_1 = require("../../lib/settings");
const accounting_service_1 = require("../accounting/accounting.service");
const inventory_service_1 = require("../inventory/inventory.service");
exports.openingBalanceInclude = {
    user: { select: { id: true, name: true } },
};
/**
 * Creates an opening-balance entry (مديونية سابقة / قيد رأس المال).
 *
 * Single balanced journal:
 *   Dr Accounts Receivable      (customer debts)
 *   Dr Inventory                (stock valuation)
 *   Cr Accounts Payable         (supplier debts)
 *   Cr Owner's Equity           (the balancing capital figure)
 *
 * It also sets each partner's `balance` and raises the opening stock
 * movements, all inside one transaction.
 */
async function createOpeningBalanceTx(tx, input) {
    const customers = (input.customers ?? []).filter((row) => (0, money_1.round2)(row.amount) > 0);
    const suppliers = (input.suppliers ?? []).filter((row) => (0, money_1.round2)(row.amount) > 0);
    const inventory = (input.inventory ?? []).filter((row) => row.quantity > 0 && (0, money_1.round2)(row.unitCost) >= 0);
    if (customers.length === 0 && suppliers.length === 0 && inventory.length === 0) {
        throw api_error_1.ApiError.badRequest('Add at least one opening balance line', 'EMPTY_OPENING_BALANCE');
    }
    const customerTotal = (0, money_1.round2)(customers.reduce((sum, row) => sum + row.amount, 0));
    const supplierTotal = (0, money_1.round2)(suppliers.reduce((sum, row) => sum + row.amount, 0));
    const inventoryTotal = (0, money_1.round2)(inventory.reduce((sum, row) => sum + row.quantity * row.unitCost, 0));
    // Guard: a partner may only appear once and must exist.
    const customerIds = customers.map((row) => row.customerId);
    const supplierIds = suppliers.map((row) => row.supplierId);
    if (new Set(customerIds).size !== customerIds.length) {
        throw api_error_1.ApiError.badRequest('Duplicate customer in opening balance', 'DUPLICATE_PARTNER');
    }
    if (new Set(supplierIds).size !== supplierIds.length) {
        throw api_error_1.ApiError.badRequest('Duplicate supplier in opening balance', 'DUPLICATE_PARTNER');
    }
    const settings = await (0, settings_1.getSettings)(tx);
    const asOfDate = input.asOfDate ?? new Date();
    const number = await (0, sequence_1.nextNumber)(tx, 'openingBalance', settings.openingBalancePrefix, asOfDate);
    // Apply partner balances.
    for (const row of customers) {
        const customer = await tx.customer.findUnique({ where: { id: row.customerId } });
        if (!customer)
            throw api_error_1.ApiError.badRequest('Customer not found', 'CUSTOMER_NOT_FOUND');
        await tx.customer.update({
            where: { id: row.customerId },
            data: { balance: { increment: (0, money_1.round2)(row.amount) } },
        });
    }
    for (const row of suppliers) {
        const supplier = await tx.supplier.findUnique({ where: { id: row.supplierId } });
        if (!supplier)
            throw api_error_1.ApiError.badRequest('Supplier not found', 'SUPPLIER_NOT_FOUND');
        await tx.supplier.update({
            where: { id: row.supplierId },
            data: { balance: { increment: (0, money_1.round2)(row.amount) } },
        });
    }
    // Raise opening stock movements.
    for (const row of inventory) {
        const location = await (0, inventory_service_1.resolveLocation)(tx, row.warehouseId);
        await (0, inventory_service_1.applyMovement)(tx, {
            type: 'OPENING',
            productId: row.productId,
            locationId: location.id,
            quantity: row.quantity,
            unitCost: (0, money_1.round2)(row.unitCost),
            reference: number,
            note: `Opening stock (${number})`,
            userId: input.userId,
        });
    }
    const entry = await tx.openingBalance.create({
        data: {
            number,
            asOfDate,
            note: input.note,
            userId: input.userId ?? null,
            customerTotal,
            supplierTotal,
            inventoryTotal,
            details: {
                customers: customers.map((row) => ({
                    customerId: row.customerId,
                    amount: (0, money_1.round2)(row.amount),
                })),
                suppliers: suppliers.map((row) => ({
                    supplierId: row.supplierId,
                    amount: (0, money_1.round2)(row.amount),
                })),
            },
        },
        include: exports.openingBalanceInclude,
    });
    // Post the balancing capital entry.
    const lines = [];
    if (customerTotal > 0) {
        lines.push({
            accountCode: accounting_service_1.ACCOUNT.RECEIVABLE,
            debit: customerTotal,
            description: `Opening receivable (${number})`,
        });
    }
    if (inventoryTotal > 0) {
        lines.push({
            accountCode: accounting_service_1.ACCOUNT.INVENTORY,
            debit: inventoryTotal,
            description: `Opening inventory (${number})`,
        });
    }
    if (supplierTotal > 0) {
        lines.push({
            accountCode: accounting_service_1.ACCOUNT.PAYABLE,
            credit: supplierTotal,
            description: `Opening payable (${number})`,
        });
    }
    const equity = (0, money_1.round2)(customerTotal + inventoryTotal - supplierTotal);
    lines.push({
        accountCode: accounting_service_1.ACCOUNT.EQUITY,
        debit: equity < 0 ? -equity : undefined,
        credit: equity > 0 ? equity : undefined,
        description: `Opening capital (${number})`,
    });
    await (0, accounting_service_1.postJournal)(tx, {
        memo: `Opening balances (${number})`,
        reference: number,
        sourceType: 'OPENING_BALANCE',
        sourceId: entry.id,
        userId: input.userId,
        entryDate: asOfDate,
        lines,
    });
    return entry;
}
async function createOpeningBalance(input) {
    return prisma_1.prisma.$transaction((tx) => createOpeningBalanceTx(tx, input));
}
/**
 * Cancels an opening-balance entry: reverses the journal, the partner
 * balances and the opening stock movements.
 */
async function cancelOpeningBalance(id, userId) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const entry = await tx.openingBalance.findUnique({
            where: { id },
            include: {
                user: { select: { id: true, name: true } },
            },
        });
        if (!entry)
            throw api_error_1.ApiError.notFound('Opening balance not found', 'OPENING_BALANCE_NOT_FOUND');
        if (entry.cancelledAt) {
            throw api_error_1.ApiError.conflict('This opening balance is already cancelled', 'ALREADY_CANCELLED');
        }
        // Reverse stock movements recorded for this entry.
        const movements = await tx.stockMovement.findMany({
            where: { type: 'OPENING', reference: entry.number },
        });
        for (const movement of movements) {
            await (0, inventory_service_1.applyMovement)(tx, {
                type: 'ADJUSTMENT',
                productId: movement.productId,
                locationId: movement.locationId,
                quantity: -movement.quantity,
                unitCost: Number(movement.unitCost ?? 0),
                reference: entry.number,
                note: `Opening stock reversed (${entry.number})`,
                userId,
            });
        }
        // Reverse any partner balances applied for this entry.
        const details = (entry.details ?? {});
        for (const row of details.customers ?? []) {
            await tx.customer.update({
                where: { id: row.customerId },
                data: { balance: { decrement: (0, money_1.round2)(row.amount) } },
            });
        }
        for (const row of details.suppliers ?? []) {
            await tx.supplier.update({
                where: { id: row.supplierId },
                data: { balance: { decrement: (0, money_1.round2)(row.amount) } },
            });
        }
        await (0, accounting_service_1.reverseJournalBySource)(tx, {
            sourceType: 'OPENING_BALANCE',
            sourceId: entry.id,
            reversalSourceType: 'OPENING_BALANCE_CANCEL',
            memo: `Opening balances reversed (${entry.number})`,
            reference: entry.number,
            userId,
        });
        return tx.openingBalance.update({
            where: { id },
            data: { cancelledAt: new Date(), cancelledBy: userId ?? null },
            include: exports.openingBalanceInclude,
        });
    });
}
async function listOpeningBalances() {
    return prisma_1.prisma.openingBalance.findMany({
        include: exports.openingBalanceInclude,
        orderBy: [{ asOfDate: 'desc' }, { createdAt: 'desc' }],
    });
}
//# sourceMappingURL=opening-balances.service.js.map