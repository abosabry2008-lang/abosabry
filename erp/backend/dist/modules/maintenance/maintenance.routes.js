"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const http_1 = require("../../lib/http");
const money_1 = require("../../lib/money");
const prisma_1 = require("../../lib/prisma");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
/**
 * Maintenance utilities — destructive operations that would otherwise need the
 * production `DATABASE_URL` in a shell. Guarded by `settings.write` (ADMIN) and
 * a typed confirmation phrase so it cannot be triggered by accident.
 */
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const CONFIRMATION = 'DELETE-ALL';
/** Normalises a product name for duplicate detection: trim, collapse inner
 * whitespace and fold case. */
function normalizeName(value) {
    return value.trim().replace(/\s+/g, ' ').toLowerCase();
}
/** Lists duplicate product names without changing anything (dry run). */
router.get('/duplicate-products', (0, authorize_1.requirePermission)('settings.write'), (0, http_1.asyncHandler)(async (_req, res) => {
    const products = await prisma_1.prisma.product.findMany({
        select: { id: true, name: true, sku: true, createdAt: true },
        orderBy: { createdAt: 'asc' },
    });
    const groups = new Map();
    for (const product of products) {
        const key = normalizeName(product.name);
        const bucket = groups.get(key);
        if (bucket)
            bucket.push(product);
        else
            groups.set(key, [product]);
    }
    const duplicates = [...groups.entries()]
        .filter(([, rows]) => rows.length > 1)
        .map(([name, rows]) => ({
        name,
        count: rows.length,
        keep: rows[0],
        remove: rows.slice(1),
    }));
    (0, http_1.ok)(res, {
        totalProducts: products.length,
        duplicateGroups: duplicates.length,
        extraRows: duplicates.reduce((sum, g) => sum + g.remove.length, 0),
        groups: duplicates,
    });
}));
/**
 * Removes duplicate products, keeping the oldest row of each name group.
 *
 * Any document or stock line that pointed at a removed duplicate is re-pointed
 * at the kept product first, so no history is lost. `confirmation` must equal
 * `DELETE-DUPLICATES`.
 */
router.post('/dedupe-products', (0, authorize_1.requirePermission)('settings.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const confirmation = String(req.body?.confirmation ?? '');
    if (confirmation !== 'DELETE-DUPLICATES') {
        res.status(400).json({
            error: {
                message: 'Type DELETE-DUPLICATES to confirm this operation',
                code: 'CONFIRMATION_REQUIRED',
            },
        });
        return;
    }
    const products = await prisma_1.prisma.product.findMany({
        select: { id: true, name: true, createdAt: true },
        orderBy: { createdAt: 'asc' },
    });
    const groups = new Map();
    for (const product of products) {
        const key = normalizeName(product.name);
        const bucket = groups.get(key);
        if (bucket)
            bucket.push(product);
        else
            groups.set(key, [product]);
    }
    let removed = 0;
    for (const rows of groups.values()) {
        if (rows.length < 2)
            continue;
        const keep = rows[0];
        const drop = rows.slice(1);
        const dropIds = drop.map((r) => r.id);
        // Re-point history at the surviving product, then merge stock levels
        // (base unit only) so quantities are not lost.
        await prisma_1.prisma.stockMovement.updateMany({
            where: { productId: { in: dropIds } },
            data: { productId: keep.id },
        });
        await prisma_1.prisma.invoiceLine.updateMany({
            where: { productId: { in: dropIds } },
            data: { productId: keep.id },
        });
        await prisma_1.prisma.salesOrderLine.updateMany({
            where: { productId: { in: dropIds } },
            data: { productId: keep.id },
        });
        await prisma_1.prisma.purchaseOrderLine.updateMany({
            where: { productId: { in: dropIds } },
            data: { productId: keep.id },
        });
        await prisma_1.prisma.returnOrderLine.updateMany({
            where: { productId: { in: dropIds } },
            data: { productId: keep.id },
        });
        // Merge stock levels per location before deleting the duplicate rows.
        const keepLevels = await prisma_1.prisma.stockLevel.findMany({
            where: { productId: keep.id },
        });
        const dropLevels = await prisma_1.prisma.stockLevel.findMany({
            where: { productId: { in: dropIds } },
        });
        for (const level of dropLevels) {
            const existing = keepLevels.find((l) => l.locationId === level.locationId);
            if (existing) {
                await prisma_1.prisma.stockLevel.update({
                    where: { id: existing.id },
                    data: { quantity: existing.quantity + level.quantity },
                });
            }
            else {
                await prisma_1.prisma.stockLevel.update({
                    where: { id: level.id },
                    data: { productId: keep.id },
                });
            }
        }
        await prisma_1.prisma.product.deleteMany({ where: { id: { in: dropIds } } });
        removed += dropIds.length;
    }
    (0, http_1.ok)(res, {
        removed,
        products: await prisma_1.prisma.product.count(),
    });
}));
/** Wipes trading data: products, customers, suppliers + everything hanging off them. */
router.post('/clear-trading-data', (0, authorize_1.requirePermission)('settings.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const confirmation = String(req.body?.confirmation ?? '');
    if (confirmation !== CONFIRMATION) {
        res.status(400).json({
            error: {
                message: `Type ${CONFIRMATION} to confirm this destructive operation`,
                code: 'CONFIRMATION_REQUIRED',
            },
        });
        return;
    }
    // Order matters: children before parents.
    await prisma_1.prisma.journalLine.deleteMany();
    await prisma_1.prisma.journalEntry.deleteMany();
    await prisma_1.prisma.collectionLine.deleteMany();
    await prisma_1.prisma.collectionVoucher.deleteMany();
    await prisma_1.prisma.payment.deleteMany();
    await prisma_1.prisma.invoiceLine.deleteMany();
    await prisma_1.prisma.invoice.deleteMany();
    await prisma_1.prisma.salesOrderLine.deleteMany();
    await prisma_1.prisma.salesOrder.deleteMany();
    await prisma_1.prisma.purchaseOrderLine.deleteMany();
    await prisma_1.prisma.purchaseOrder.deleteMany();
    await prisma_1.prisma.returnOrderLine.deleteMany();
    await prisma_1.prisma.returnOrder.deleteMany();
    await prisma_1.prisma.openingBalance.deleteMany();
    await prisma_1.prisma.accountSettlement.deleteMany();
    await prisma_1.prisma.stockMovement.deleteMany();
    await prisma_1.prisma.stockLevel.deleteMany();
    await prisma_1.prisma.product.deleteMany();
    await prisma_1.prisma.supplier.deleteMany();
    await prisma_1.prisma.customer.deleteMany();
    // Reset document counters so new documents start from 1 again.
    await prisma_1.prisma.sequence.deleteMany();
    (0, http_1.ok)(res, {
        products: await prisma_1.prisma.product.count(),
        customers: await prisma_1.prisma.customer.count(),
        suppliers: await prisma_1.prisma.supplier.count(),
    });
}));
/**
 * Repairs inventory quantities that were doubled by importing the same opening
 * stock file twice.
 *
 * When duplicate product rows were merged, their stock movements were kept and
 * their stock levels summed, so each product ended up with two identical
 * `OPENING` movements and a doubled `StockLevel.quantity`.
 *
 * This endpoint groups movements by (product, location, type, quantity,
 * reference) and keeps only the first of each group, subtracting the removed
 * quantity from the matching stock level. Only `OPENING` movements are touched,
 * so real receiving/selling history is never altered.
 *
 * `confirmation` must equal `FIX-OPENING-DUPLICATES`. Pass `dryRun: true` to
 * see what would change without writing anything.
 */
router.post('/fix-opening-duplicates', (0, authorize_1.requirePermission)('settings.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const body = (req.body ?? {});
    const confirmation = String(body.confirmation ?? '');
    const dryRun = body.dryRun === true;
    if (confirmation !== 'FIX-OPENING-DUPLICATES') {
        res.status(400).json({
            error: {
                message: 'Type FIX-OPENING-DUPLICATES to confirm this operation',
                code: 'CONFIRMATION_REQUIRED',
            },
        });
        return;
    }
    const movements = await prisma_1.prisma.stockMovement.findMany({
        where: { type: 'OPENING' },
        select: {
            id: true,
            productId: true,
            locationId: true,
            quantity: true,
            type: true,
            reference: true,
            createdAt: true,
            product: { select: { name: true } },
        },
        orderBy: { createdAt: 'asc' },
    });
    // Group identical opening movements; the first (oldest) of each group stays.
    const seen = new Set();
    const toRemove = [];
    for (const movement of movements) {
        const key = [
            movement.productId,
            movement.locationId ?? '',
            movement.type,
            movement.quantity,
            movement.reference ?? '',
        ].join('::');
        if (seen.has(key)) {
            toRemove.push(movement);
        }
        else {
            seen.add(key);
        }
    }
    if (dryRun) {
        (0, http_1.ok)(res, {
            dryRun: true,
            openingMovements: movements.length,
            duplicates: toRemove.length,
            affectedProducts: new Set(toRemove.map((m) => m.productId)).size,
            sample: toRemove.slice(0, 20).map((m) => ({
                product: m.product.name,
                quantity: m.quantity,
                createdAt: m.createdAt,
            })),
        });
        return;
    }
    let levelAdjustments = 0;
    for (const movement of toRemove) {
        await prisma_1.prisma.stockMovement.delete({ where: { id: movement.id } });
        // Give the quantity back to the kept movement by reducing the doubled
        // stock level.
        const level = await prisma_1.prisma.stockLevel.findUnique({
            where: {
                productId_locationId: {
                    productId: movement.productId,
                    locationId: movement.locationId,
                },
            },
        });
        if (level) {
            await prisma_1.prisma.stockLevel.update({
                where: { id: level.id },
                data: { quantity: Math.max(0, level.quantity - movement.quantity) },
            });
            levelAdjustments += 1;
        }
    }
    (0, http_1.ok)(res, {
        openingMovements: movements.length,
        removedMovements: toRemove.length,
        levelAdjustments,
        products: await prisma_1.prisma.product.count(),
    });
}));
/**
 * Repairs customer balances that were silently wiped by the old balance
 * recalculation.
 *
 * `recalcCustomerBalance` used to rebuild a customer's balance from their
 * invoices and settlements only, ignoring the opening balance. Any customer who
 * had an invoice issued, a payment recorded or a settlement made after their
 * opening balance was entered lost it.
 *
 * This endpoint recomputes every customer balance with the corrected formula
 * (opening balance read back from the ledger + open invoices + live
 * settlements) and writes it back.
 *
 * `confirmation` must equal `FIX-CUSTOMER-BALANCES`. Pass `dryRun: true` to see
 * which customers would change without writing anything.
 */
router.post('/fix-customer-balances', (0, authorize_1.requirePermission)('settings.write'), (0, http_1.asyncHandler)(async (req, res) => {
    const body = (req.body ?? {});
    const confirmation = String(body.confirmation ?? '');
    const dryRun = body.dryRun === true;
    if (confirmation !== 'FIX-CUSTOMER-BALANCES') {
        res.status(400).json({
            error: {
                message: 'Type FIX-CUSTOMER-BALANCES to confirm this operation',
                code: 'CONFIRMATION_REQUIRED',
            },
        });
        return;
    }
    const customers = await prisma_1.prisma.customer.findMany({
        select: { id: true, code: true, name: true, balance: true },
        orderBy: { code: 'asc' },
    });
    // Bulk opening-balance documents store per-customer amounts in `details`.
    const docs = await prisma_1.prisma.openingBalance.findMany({
        where: { cancelledAt: null },
        select: { details: true },
    });
    const bulkOpening = new Map();
    for (const doc of docs) {
        const details = doc.details;
        for (const row of details?.customers ?? []) {
            if (!row.customerId)
                continue;
            bulkOpening.set(row.customerId, (bulkOpening.get(row.customerId) ?? 0) + Number(row.amount ?? 0));
        }
    }
    const changes = [];
    for (const customer of customers) {
        const [aggregate, settlements, openingLines] = await Promise.all([
            prisma_1.prisma.invoice.aggregate({
                where: {
                    customerId: customer.id,
                    status: { in: ['ISSUED', 'PARTIALLY_PAID', 'PAID'] },
                },
                _sum: { balance: true },
            }),
            prisma_1.prisma.accountSettlement.findMany({
                where: { customerId: customer.id, cancelledAt: null },
                select: { direction: true, amount: true },
            }),
            prisma_1.prisma.journalLine.findMany({
                where: {
                    account: { code: '1100' },
                    journalEntry: { sourceType: 'OPENING_CUSTOMER', sourceId: customer.id },
                },
                select: { debit: true, credit: true },
            }),
        ]);
        const opening = openingLines.reduce((sum, l) => sum + Number(l.debit) - Number(l.credit), 0) +
            (bulkOpening.get(customer.id) ?? 0);
        const invoiceBalance = Number(aggregate._sum.balance ?? 0);
        const adjustment = settlements.reduce((sum, row) => sum + (row.direction === 'INCREASE' ? Number(row.amount) : -Number(row.amount)), 0);
        const target = (0, money_1.round2)(opening + invoiceBalance + adjustment);
        const current = (0, money_1.round2)(Number(customer.balance));
        if (Math.abs(target - current) > 0.009) {
            changes.push({ code: customer.code ?? '', name: customer.name, from: current, to: target });
            if (!dryRun) {
                await prisma_1.prisma.customer.update({
                    where: { id: customer.id },
                    data: { balance: target },
                });
            }
        }
    }
    (0, http_1.ok)(res, {
        dryRun,
        customers: customers.length,
        changed: changes.length,
        restoredTotal: (0, money_1.round2)(changes.reduce((sum, c) => sum + (c.to - c.from), 0)),
        sample: changes.slice(0, 25),
    });
}));
exports.default = router;
//# sourceMappingURL=maintenance.routes.js.map