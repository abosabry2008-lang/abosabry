"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.applyMovement = applyMovement;
exports.stockAt = stockAt;
exports.totalStockByProduct = totalStockByProduct;
exports.receiveStock = receiveStock;
exports.dispatchStock = dispatchStock;
exports.adjustStock = adjustStock;
exports.transferStock = transferStock;
exports.resolveLocation = resolveLocation;
exports.drawFromWarehouse = drawFromWarehouse;
exports.cycleCount = cycleCount;
exports.lowStockProducts = lowStockProducts;
const api_error_1 = require("../../lib/api-error");
const prisma_1 = require("../../lib/prisma");
/**
 * Applies a stock delta to a location and records the audit movement.
 * Must be called inside a transaction.
 */
async function applyMovement(tx, input) {
    if (input.quantity === 0) {
        throw api_error_1.ApiError.badRequest('Movement quantity must not be zero', 'ZERO_MOVEMENT');
    }
    const location = await tx.location.findUnique({ where: { id: input.locationId } });
    if (!location)
        throw api_error_1.ApiError.badRequest('Location not found', 'LOCATION_NOT_FOUND');
    const product = await tx.product.findUnique({ where: { id: input.productId } });
    if (!product)
        throw api_error_1.ApiError.badRequest('Product not found', 'PRODUCT_NOT_FOUND');
    const level = await tx.stockLevel.upsert({
        where: {
            productId_locationId: { productId: input.productId, locationId: input.locationId },
        },
        create: {
            productId: input.productId,
            locationId: input.locationId,
            warehouseId: location.warehouseId,
            quantity: input.quantity,
        },
        update: { quantity: { increment: input.quantity } },
    });
    await tx.stockMovement.create({
        data: {
            type: input.type,
            productId: input.productId,
            locationId: input.locationId,
            warehouseId: location.warehouseId,
            quantity: input.quantity,
            unitCost: input.unitCost ?? 0,
            balanceAfter: level.quantity,
            reference: input.reference,
            note: input.note,
            userId: input.userId,
        },
    });
    return level.quantity;
}
async function stockAt(locationId, productId) {
    const level = await prisma_1.prisma.stockLevel.findUnique({
        where: { productId_locationId: { productId, locationId } },
    });
    return level?.quantity ?? 0;
}
/** Total stock per product across all locations. */
async function totalStockByProduct(productIds) {
    if (productIds.length === 0)
        return new Map();
    const rows = await prisma_1.prisma.stockLevel.groupBy({
        by: ['productId'],
        where: { productId: { in: productIds } },
        _sum: { quantity: true },
    });
    return new Map(rows.map((row) => [row.productId, row._sum.quantity ?? 0]));
}
async function receiveStock(input) {
    if (input.quantity <= 0)
        throw api_error_1.ApiError.badRequest('Quantity must be greater than zero');
    const balance = await prisma_1.prisma.$transaction((tx) => applyMovement(tx, {
        type: 'RECEIVE',
        productId: input.productId,
        locationId: input.locationId,
        quantity: Math.abs(input.quantity),
        unitCost: input.unitCost,
        reference: input.reference,
        note: input.note,
        userId: input.userId,
    }));
    return { balance };
}
async function dispatchStock(input) {
    if (input.quantity <= 0)
        throw api_error_1.ApiError.badRequest('Quantity must be greater than zero');
    const quantity = Math.abs(input.quantity);
    const balance = await prisma_1.prisma.$transaction(async (tx) => {
        const current = await tx.stockLevel.findUnique({
            where: { productId_locationId: { productId: input.productId, locationId: input.locationId } },
        });
        const available = current?.quantity ?? 0;
        if (!input.allowNegative && available < quantity) {
            throw api_error_1.ApiError.badRequest(`Insufficient stock: ${available} available, ${quantity} requested`, 'INSUFFICIENT_STOCK', { available, requested: quantity });
        }
        return applyMovement(tx, {
            type: 'DISPATCH',
            productId: input.productId,
            locationId: input.locationId,
            quantity: -quantity,
            unitCost: input.unitCost,
            reference: input.reference,
            note: input.note,
            userId: input.userId,
        });
    });
    return { balance };
}
async function adjustStock(input) {
    if (input.quantity === 0)
        throw api_error_1.ApiError.badRequest('Adjustment quantity must not be zero');
    const balance = await prisma_1.prisma.$transaction((tx) => applyMovement(tx, {
        type: 'ADJUSTMENT',
        productId: input.productId,
        locationId: input.locationId,
        quantity: input.quantity,
        note: input.reason,
        userId: input.userId,
    }));
    return { balance };
}
async function transferStock(input) {
    if (input.quantity <= 0)
        throw api_error_1.ApiError.badRequest('Quantity must be greater than zero');
    if (input.fromLocationId === input.toLocationId) {
        throw api_error_1.ApiError.badRequest('Source and destination locations must differ');
    }
    const quantity = Math.abs(input.quantity);
    return prisma_1.prisma.$transaction(async (tx) => {
        const from = await tx.stockLevel.findUnique({
            where: { productId_locationId: { productId: input.productId, locationId: input.fromLocationId } },
        });
        const available = from?.quantity ?? 0;
        if (available < quantity) {
            throw api_error_1.ApiError.badRequest(`Insufficient stock at source: ${available} available, ${quantity} requested`, 'INSUFFICIENT_STOCK', { available, requested: quantity });
        }
        const fromBalance = await applyMovement(tx, {
            type: 'TRANSFER_OUT',
            productId: input.productId,
            locationId: input.fromLocationId,
            quantity: -quantity,
            note: input.note,
            userId: input.userId,
        });
        const toBalance = await applyMovement(tx, {
            type: 'TRANSFER_IN',
            productId: input.productId,
            locationId: input.toLocationId,
            quantity,
            note: input.note,
            userId: input.userId,
        });
        return { fromBalance, toBalance };
    });
}
/** Returns the first active location of a warehouse, creating a MAIN one if needed. */
async function resolveLocation(tx, warehouseId) {
    const existing = await tx.location.findFirst({
        where: { warehouseId, active: true },
        orderBy: { code: 'asc' },
    });
    if (existing)
        return existing;
    return tx.location.create({ data: { warehouseId, code: 'MAIN', name: 'Main' } });
}
/**
 * Removes `quantity` of a product from a warehouse, spreading the deduction
 * across its active locations (lowest location code first) so stock is never
 * stranded in one aisle. Throws when the warehouse as a whole is short.
 * Must be called inside a transaction.
 */
async function drawFromWarehouse(tx, input) {
    const { warehouseId, productId, quantity } = input;
    if (quantity <= 0)
        throw api_error_1.ApiError.badRequest('Quantity must be greater than zero', 'ZERO_MOVEMENT');
    const locations = await tx.location.findMany({
        where: { warehouseId, active: true },
        orderBy: { code: 'asc' },
        select: { id: true },
    });
    const levels = locations.length
        ? await tx.stockLevel.findMany({
            where: {
                productId,
                locationId: { in: locations.map((location) => location.id) },
                quantity: { gt: 0 },
            },
        })
        : [];
    const available = levels.reduce((sum, level) => sum + level.quantity, 0);
    if (available < quantity) {
        throw api_error_1.ApiError.badRequest(`Insufficient stock: ${available} available, ${quantity} required`, 'INSUFFICIENT_STOCK', { productId, available, requested: quantity });
    }
    // Consume the lowest-coded location first for a deterministic draw-down.
    const order = new Map(locations.map((location, index) => [location.id, index]));
    levels.sort((a, b) => (order.get(a.locationId) ?? 0) - (order.get(b.locationId) ?? 0));
    const draws = [];
    let remaining = quantity;
    for (const level of levels) {
        if (remaining <= 0)
            break;
        const take = Math.min(level.quantity, remaining);
        await applyMovement(tx, {
            type: input.type,
            productId,
            locationId: level.locationId,
            quantity: -take,
            unitCost: input.unitCost,
            reference: input.reference,
            note: input.note,
            userId: input.userId,
        });
        draws.push({ locationId: level.locationId, quantity: take });
        remaining -= take;
    }
    return draws;
}
async function cycleCount(input) {
    return prisma_1.prisma.$transaction(async (tx) => {
        const results = [];
        for (const item of input.items) {
            const level = await tx.stockLevel.findUnique({
                where: { productId_locationId: { productId: item.productId, locationId: input.locationId } },
            });
            const expected = level?.quantity ?? 0;
            const difference = item.countedQty - expected;
            if (difference !== 0) {
                await applyMovement(tx, {
                    type: 'CYCLE_COUNT',
                    productId: item.productId,
                    locationId: input.locationId,
                    quantity: difference,
                    note: input.note ?? 'Cycle count adjustment',
                    userId: input.userId,
                });
            }
            results.push({ productId: item.productId, expected, counted: item.countedQty, difference });
        }
        return results;
    });
}
/** Products whose total stock has reached or fallen below their reorder level. */
async function lowStockProducts(warehouseId) {
    const products = await prisma_1.prisma.product.findMany({
        where: {
            deletedAt: null,
            active: true,
            trackInventory: true,
            reorderLevel: { gt: 0 },
        },
        include: {
            category: { select: { id: true, name: true } },
            currency: { select: { id: true, code: true, symbol: true } },
            stockLevels: { select: { quantity: true, warehouseId: true } },
        },
        orderBy: { name: 'asc' },
    });
    return products
        .map((product) => {
        const levels = warehouseId
            ? product.stockLevels.filter((level) => level.warehouseId === warehouseId)
            : product.stockLevels;
        const quantity = levels.reduce((sum, level) => sum + level.quantity, 0);
        const { stockLevels, ...rest } = product;
        void stockLevels;
        return { product: rest, quantity, shortage: product.reorderLevel - quantity };
    })
        .filter((row) => row.quantity <= row.product.reorderLevel);
}
//# sourceMappingURL=inventory.service.js.map