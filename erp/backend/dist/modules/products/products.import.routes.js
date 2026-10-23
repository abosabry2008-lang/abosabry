"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const api_error_1 = require("../../lib/api-error");
const http_1 = require("../../lib/http");
const prisma_1 = require("../../lib/prisma");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const inventory_service_1 = require("../inventory/inventory.service");
/**
 * Bulk product import (استيراد الأصناف من Excel).
 *
 * Rows look like `{ name, quantity, costPrice, salePrice?, sku? }` — the columns
 * the shop exports from Excel: الصنف، العدد، سعر التكلفة، سعر البيع. Matching is
 * by `sku`: an existing code updates the product, a new one is created. When the
 * code column is empty a code is generated automatically, and when the sale
 * price is left empty it defaults to the cost price + 3%.
 */
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const rowSchema = zod_1.z.object({
    name: zod_1.z.string().min(1).max(200),
    sku: zod_1.z.string().max(64).nullable().optional(),
    barcode: zod_1.z.string().max(64).nullable().optional(),
    // The columns the shop exports from Excel:
    // (الصنف، العدد، سعر التكلفة، سعر البيع). Legacy keys are still accepted.
    price: zod_1.z.number().min(0).optional(),
    salePrice: zod_1.z.number().min(0).optional(),
    costPrice: zod_1.z.number().min(0).optional(),
    quantity: zod_1.z.number().optional(),
    boxesPerCarton: zod_1.z.number().int().min(0).optional(),
    cartonPrice: zod_1.z.number().min(0).optional(),
    boxPrice: zod_1.z.number().min(0).optional(),
    unit: zod_1.z.string().max(16).optional(),
});
const importSchema = zod_1.z.object({
    warehouseId: zod_1.z.string().min(1).nullable().optional(),
    /** When true, existing products have their stock set to the imported qty. */
    adjustStock: zod_1.z.boolean().optional(),
    rows: zod_1.z.array(rowSchema).min(1).max(5000),
});
/** Random, human-readable SKU such as `SKU-7F3K9Q`. */
function randomSku(existing) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    for (let attempt = 0; attempt < 50; attempt++) {
        let code = '';
        for (let i = 0; i < 6; i++) {
            code += alphabet[Math.floor(Math.random() * alphabet.length)];
        }
        const sku = `SKU-${code}`;
        if (!existing.has(sku)) {
            existing.add(sku);
            return sku;
        }
    }
    // Extremely unlikely: fall back to a timestamp-based code.
    const sku = `SKU-${Date.now().toString(36).toUpperCase()}`;
    existing.add(sku);
    return sku;
}
/** Default sale price: cost + 3% when the sheet leaves it blank. */
function defaultSalePrice(cost) {
    return Math.round(cost * 1.03 * 100) / 100;
}
/** Resolves a row's cost and sale price, defaulting sale to cost + 3%. */
function resolvePrices(row) {
    const cost = row.costPrice ?? 0;
    const explicit = row.salePrice ?? row.price;
    const sale = explicit != null && explicit > 0 ? explicit : defaultSalePrice(cost);
    return { cost, sale };
}
router.post('/import', (0, authorize_1.requirePermission)('products.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const parsed = importSchema.safeParse(req.body);
    if (!parsed.success) {
        throw api_error_1.ApiError.badRequest('Invalid import payload', 'INVALID_IMPORT', parsed.error.flatten());
    }
    const { rows, warehouseId, adjustStock } = parsed.data;
    // Pre-load existing codes so generated ones never clash.
    const existing = new Set((await prisma_1.prisma.product.findMany({ select: { sku: true } })).map((p) => p.sku));
    // All imported products share one warehouse (the default one when omitted).
    let targetWarehouseId = warehouseId ?? null;
    if (!targetWarehouseId) {
        const first = await prisma_1.prisma.warehouse.findFirst({
            where: { active: true },
            orderBy: { code: 'asc' },
        });
        targetWarehouseId = first?.id ?? null;
    }
    const result = await prisma_1.prisma.$transaction(async (tx) => {
        const out = [];
        let created = 0;
        let updated = 0;
        let skipped = 0;
        // Resolve the location once, lazily — only when we actually add stock.
        let locationId = null;
        const location = async () => {
            if (!targetWarehouseId)
                return null;
            if (!locationId) {
                const resolved = await (0, inventory_service_1.resolveLocation)(tx, targetWarehouseId);
                locationId = resolved.id;
            }
            return locationId;
        };
        for (const row of rows) {
            const name = row.name.trim();
            const code = (row.sku ?? '').trim();
            try {
                const existingProduct = code
                    ? await tx.product.findFirst({
                        where: { sku: code },
                        select: { id: true, deletedAt: true },
                    })
                    : null;
                if (existingProduct) {
                    const hasAnyPrice = row.costPrice != null || row.salePrice != null || row.price != null;
                    const prices = resolvePrices(row);
                    await tx.product.update({
                        where: { id: existingProduct.id },
                        data: {
                            name,
                            deletedAt: null,
                            active: true,
                            // Just the cost? → sale becomes cost + 3% and vice versa.
                            ...(hasAnyPrice ? { costPrice: prices.cost, salePrice: prices.sale } : {}),
                            ...(row.boxesPerCarton != null ? { boxesPerCarton: row.boxesPerCarton } : {}),
                            ...(row.boxPrice != null ? { boxPrice: row.boxPrice } : {}),
                            ...(row.cartonPrice != null ? { cartonPrice: row.cartonPrice } : {}),
                            ...(row.unit ? { unit: row.unit } : {}),
                        },
                    });
                    let stockAdded = 0;
                    // Only touch stock for an existing product when explicitly asked,
                    // and never for one that was previously deleted.
                    if (adjustStock && row.quantity != null && !existingProduct.deletedAt) {
                        const loc = await location();
                        if (loc && row.quantity !== 0) {
                            const current = await tx.stockLevel.findUnique({
                                where: { productId_locationId: { productId: existingProduct.id, locationId: loc } },
                                select: { quantity: true },
                            });
                            const delta = row.quantity - (current?.quantity ?? 0);
                            if (delta !== 0) {
                                await (0, inventory_service_1.applyMovement)(tx, {
                                    type: 'ADJUSTMENT',
                                    productId: existingProduct.id,
                                    locationId: loc,
                                    quantity: delta,
                                    unitCost: row.costPrice ?? 0,
                                    reference: 'IMPORT',
                                    note: 'Stock set by Excel import',
                                    userId: (0, authenticate_1.currentUser)(req).id,
                                });
                                stockAdded = delta;
                            }
                        }
                    }
                    updated++;
                    out.push({ name, sku: code, action: 'updated', stockAdded });
                }
                else {
                    const sku = code || randomSku(existing);
                    const prices = resolvePrices(row);
                    const product = await tx.product.create({
                        data: {
                            sku,
                            name,
                            unit: row.unit ?? 'pc',
                            costPrice: prices.cost,
                            salePrice: prices.sale,
                            boxesPerCarton: row.boxesPerCarton ?? 0,
                            ...(row.boxPrice != null ? { boxPrice: row.boxPrice } : {}),
                            ...(row.cartonPrice != null ? { cartonPrice: row.cartonPrice } : {}),
                            active: true,
                            trackInventory: true,
                            ...(row.barcode ? { barcode: row.barcode } : {}),
                        },
                        select: { id: true },
                    });
                    existing.add(sku);
                    let stockAdded = 0;
                    if (row.quantity != null && row.quantity > 0) {
                        const loc = await location();
                        if (loc) {
                            await (0, inventory_service_1.applyMovement)(tx, {
                                type: 'OPENING',
                                productId: product.id,
                                locationId: loc,
                                quantity: row.quantity,
                                unitCost: prices.cost,
                                reference: 'IMPORT',
                                note: 'Opening stock from Excel import',
                                userId: (0, authenticate_1.currentUser)(req).id,
                            });
                            stockAdded = row.quantity;
                        }
                    }
                    created++;
                    out.push({ name, sku, action: 'created', stockAdded });
                }
            }
            catch (error) {
                skipped++;
                out.push({
                    name,
                    sku: code,
                    action: 'skipped',
                    reason: error instanceof Error ? error.message : 'Unknown error',
                    stockAdded: 0,
                });
            }
        }
        return { created, updated, skipped, rows: out };
    });
    (0, http_1.ok)(res, result);
}));
exports.default = router;
//# sourceMappingURL=products.import.routes.js.map