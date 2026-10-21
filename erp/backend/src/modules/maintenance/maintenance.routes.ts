import { Router } from 'express';
import { asyncHandler, ok } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { authenticate } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';

/**
 * Maintenance utilities — destructive operations that would otherwise need the
 * production `DATABASE_URL` in a shell. Guarded by `settings.write` (ADMIN) and
 * a typed confirmation phrase so it cannot be triggered by accident.
 */
const router = Router();
router.use(authenticate);

const CONFIRMATION = 'DELETE-ALL';

/** Normalises a product name for duplicate detection: trim, collapse inner
 * whitespace and fold case. */
function normalizeName(value: string): string {
  return value.trim().replace(/\s+/g, ' ').toLowerCase();
}

/** Lists duplicate product names without changing anything (dry run). */
router.get(
  '/duplicate-products',
  requirePermission('settings.write'),
  asyncHandler(async (_req, res) => {
    const products = await prisma.product.findMany({
      select: { id: true, name: true, sku: true, createdAt: true },
      orderBy: { createdAt: 'asc' },
    });

    const groups = new Map<string, typeof products>();
    for (const product of products) {
      const key = normalizeName(product.name);
      const bucket = groups.get(key);
      if (bucket) bucket.push(product);
      else groups.set(key, [product]);
    }

    const duplicates = [...groups.entries()]
      .filter(([, rows]) => rows.length > 1)
      .map(([name, rows]) => ({
        name,
        count: rows.length,
        keep: rows[0],
        remove: rows.slice(1),
      }));

    ok(res, {
      totalProducts: products.length,
      duplicateGroups: duplicates.length,
      extraRows: duplicates.reduce((sum, g) => sum + g.remove.length, 0),
      groups: duplicates,
    });
  }),
);

/**
 * Removes duplicate products, keeping the oldest row of each name group.
 *
 * Any document or stock line that pointed at a removed duplicate is re-pointed
 * at the kept product first, so no history is lost. `confirmation` must equal
 * `DELETE-DUPLICATES`.
 */
router.post(
  '/dedupe-products',
  requirePermission('settings.write'),
  asyncHandler(async (req, res) => {
    const confirmation = String((req.body as { confirmation?: unknown })?.confirmation ?? '');
    if (confirmation !== 'DELETE-DUPLICATES') {
      res.status(400).json({
        error: {
          message: 'Type DELETE-DUPLICATES to confirm this operation',
          code: 'CONFIRMATION_REQUIRED',
        },
      });
      return;
    }

    const products = await prisma.product.findMany({
      select: { id: true, name: true, createdAt: true },
      orderBy: { createdAt: 'asc' },
    });

    const groups = new Map<string, typeof products>();
    for (const product of products) {
      const key = normalizeName(product.name);
      const bucket = groups.get(key);
      if (bucket) bucket.push(product);
      else groups.set(key, [product]);
    }

    let removed = 0;

    for (const rows of groups.values()) {
      if (rows.length < 2) continue;
      const keep = rows[0];
      const drop = rows.slice(1);
      const dropIds = drop.map((r) => r.id);

      // Re-point history at the surviving product, then merge stock levels
      // (base unit only) so quantities are not lost.
      await prisma.stockMovement.updateMany({
        where: { productId: { in: dropIds } },
        data: { productId: keep.id },
      });
      await prisma.invoiceLine.updateMany({
        where: { productId: { in: dropIds } },
        data: { productId: keep.id },
      });
      await prisma.salesOrderLine.updateMany({
        where: { productId: { in: dropIds } },
        data: { productId: keep.id },
      });
      await prisma.purchaseOrderLine.updateMany({
        where: { productId: { in: dropIds } },
        data: { productId: keep.id },
      });
      await prisma.returnOrderLine.updateMany({
        where: { productId: { in: dropIds } },
        data: { productId: keep.id },
      });

      // Merge stock levels per location before deleting the duplicate rows.
      const keepLevels = await prisma.stockLevel.findMany({
        where: { productId: keep.id },
      });
      const dropLevels = await prisma.stockLevel.findMany({
        where: { productId: { in: dropIds } },
      });
      for (const level of dropLevels) {
        const existing = keepLevels.find((l) => l.locationId === level.locationId);
        if (existing) {
          await prisma.stockLevel.update({
            where: { id: existing.id },
            data: { quantity: existing.quantity + level.quantity },
          });
        } else {
          await prisma.stockLevel.update({
            where: { id: level.id },
            data: { productId: keep.id },
          });
        }
      }

      await prisma.product.deleteMany({ where: { id: { in: dropIds } } });
      removed += dropIds.length;
    }

    ok(res, {
      removed,
      products: await prisma.product.count(),
    });
  }),
);

/** Wipes trading data: products, customers, suppliers + everything hanging off them. */
router.post(
  '/clear-trading-data',
  requirePermission('settings.write'),
  asyncHandler(async (req, res) => {
    const confirmation = String((req.body as { confirmation?: unknown })?.confirmation ?? '');
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
    await prisma.journalLine.deleteMany();
    await prisma.journalEntry.deleteMany();

    await prisma.collectionLine.deleteMany();
    await prisma.collectionVoucher.deleteMany();

    await prisma.payment.deleteMany();

    await prisma.invoiceLine.deleteMany();
    await prisma.invoice.deleteMany();

    await prisma.salesOrderLine.deleteMany();
    await prisma.salesOrder.deleteMany();

    await prisma.purchaseOrderLine.deleteMany();
    await prisma.purchaseOrder.deleteMany();

    await prisma.returnOrderLine.deleteMany();
    await prisma.returnOrder.deleteMany();

    await prisma.openingBalance.deleteMany();
    await prisma.accountSettlement.deleteMany();

    await prisma.stockMovement.deleteMany();
    await prisma.stockLevel.deleteMany();

    await prisma.product.deleteMany();
    await prisma.supplier.deleteMany();
    await prisma.customer.deleteMany();

    // Reset document counters so new documents start from 1 again.
    await prisma.sequence.deleteMany();

    ok(res, {
      products: await prisma.product.count(),
      customers: await prisma.customer.count(),
      suppliers: await prisma.supplier.count(),
    });
  }),
);

export default router;
