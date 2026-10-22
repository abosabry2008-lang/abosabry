import { Router } from 'express';
import { asyncHandler, ok } from '../../lib/http';
import { round2 } from '../../lib/money';
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
router.post(
  '/fix-opening-duplicates',
  requirePermission('settings.write'),
  asyncHandler(async (req, res) => {
    const body = (req.body ?? {}) as { confirmation?: unknown; dryRun?: unknown };
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

    const movements = await prisma.stockMovement.findMany({
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
    const seen = new Set<string>();
    const toRemove: typeof movements = [];
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
      } else {
        seen.add(key);
      }
    }

    if (dryRun) {
      ok(res, {
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
      await prisma.stockMovement.delete({ where: { id: movement.id } });

      // Give the quantity back to the kept movement by reducing the doubled
      // stock level.
      const level = await prisma.stockLevel.findUnique({
        where: {
          productId_locationId: {
            productId: movement.productId,
            locationId: movement.locationId,
          },
        },
      });
      if (level) {
        await prisma.stockLevel.update({
          where: { id: level.id },
          data: { quantity: Math.max(0, level.quantity - movement.quantity) },
        });
        levelAdjustments += 1;
      }
    }

    ok(res, {
      openingMovements: movements.length,
      removedMovements: toRemove.length,
      levelAdjustments,
      products: await prisma.product.count(),
    });
  }),
);

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
router.post(
  '/fix-customer-balances',
  requirePermission('settings.write'),
  asyncHandler(async (req, res) => {
    const body = (req.body ?? {}) as { confirmation?: unknown; dryRun?: unknown };
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

    const customers = await prisma.customer.findMany({
      select: { id: true, code: true, name: true, balance: true },
      orderBy: { code: 'asc' },
    });

    // Bulk opening-balance documents store per-customer amounts in `details`.
    const docs = await prisma.openingBalance.findMany({
      where: { cancelledAt: null },
      select: { details: true },
    });
    const bulkOpening = new Map<string, number>();
    for (const doc of docs) {
      const details = doc.details as { customers?: { customerId?: string; amount?: number }[] } | null;
      for (const row of details?.customers ?? []) {
        if (!row.customerId) continue;
        bulkOpening.set(
          row.customerId,
          (bulkOpening.get(row.customerId) ?? 0) + Number(row.amount ?? 0),
        );
      }
    }

    const changes: { code: string; name: string; from: number; to: number }[] = [];

    for (const customer of customers) {
      const [aggregate, settlements, openingLines] = await Promise.all([
        prisma.invoice.aggregate({
          where: {
            customerId: customer.id,
            status: { in: ['ISSUED', 'PARTIALLY_PAID', 'PAID'] },
          },
          _sum: { balance: true },
        }),
        prisma.accountSettlement.findMany({
          where: { customerId: customer.id, cancelledAt: null },
          select: { direction: true, amount: true },
        }),
        prisma.journalLine.findMany({
          where: {
            account: { code: '1100' },
            journalEntry: { sourceType: 'OPENING_CUSTOMER', sourceId: customer.id },
          },
          select: { debit: true, credit: true },
        }),
      ]);

      const opening =
        openingLines.reduce((sum, l) => sum + Number(l.debit) - Number(l.credit), 0) +
        (bulkOpening.get(customer.id) ?? 0);
      const invoiceBalance = Number(aggregate._sum.balance ?? 0);
      const adjustment = settlements.reduce(
        (sum, row) => sum + (row.direction === 'INCREASE' ? Number(row.amount) : -Number(row.amount)),
        0,
      );
      const target = round2(opening + invoiceBalance + adjustment);
      const current = round2(Number(customer.balance));

      if (Math.abs(target - current) > 0.009) {
        changes.push({ code: customer.code ?? '', name: customer.name, from: current, to: target });
        if (!dryRun) {
          await prisma.customer.update({
            where: { id: customer.id },
            data: { balance: target },
          });
        }
      }
    }

    ok(res, {
      dryRun,
      customers: customers.length,
      changed: changes.length,
      restoredTotal: round2(changes.reduce((sum, c) => sum + (c.to - c.from), 0)),
      sample: changes.slice(0, 25),
    });
  }),
);

export default router;
