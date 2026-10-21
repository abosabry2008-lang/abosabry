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
