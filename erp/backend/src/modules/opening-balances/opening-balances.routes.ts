import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, created, ok } from '../../lib/http';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission, requireAdmin } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import {
  cancelOpeningBalance,
  createOpeningBalance,
  listOpeningBalances,
} from './opening-balances.service';

const router = Router();
router.use(authenticate);

const createSchema = z.object({
  asOfDate: z.coerce.date().optional(),
  note: z.string().max(500).nullable().optional(),
  customers: z
    .array(
      z.object({
        customerId: z.string().min(1),
        amount: z.number().nonnegative(),
      }),
    )
    .optional(),
  suppliers: z
    .array(
      z.object({
        supplierId: z.string().min(1),
        amount: z.number().nonnegative(),
      }),
    )
    .optional(),
  inventory: z
    .array(
      z.object({
        warehouseId: z.string().min(1),
        productId: z.string().min(1),
        quantity: z.number().int().positive(),
        unitCost: z.number().nonnegative(),
      }),
    )
    .optional(),
});

router.get(
  '/',
  requirePermission('openingBalances.read'),
  asyncHandler(async (_req, res) => {
    ok(res, await listOpeningBalances());
  }),
);

router.post(
  '/',
  requirePermission('openingBalances.write'),
  validateBody(createSchema),
  asyncHandler(async (req, res) => {
    const entry = await createOpeningBalance({
      ...req.body,
      userId: currentUser(req).id,
    });
    created(res, entry);
  }),
);

router.post(
  '/:id/cancel',
  requirePermission('openingBalances.write'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const entry = await cancelOpeningBalance(req.params.id, currentUser(req).id);
    ok(res, entry);
  }),
);

export default router;
