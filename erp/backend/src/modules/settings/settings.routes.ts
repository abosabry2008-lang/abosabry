import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, ok } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { getSettings, invalidateSettingsCache } from '../../lib/settings';
import { authenticate } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';

const router = Router();
router.use(authenticate);

const updateSchema = z.object({
  companyName: z.string().min(1).optional(),
  companyEmail: z.string().nullable().optional(),
  companyPhone: z.string().nullable().optional(),
  companyAddress: z.string().nullable().optional(),
  logoUrl: z.string().url().nullable().optional().or(z.literal('').nullable()),
  commercialRegisterNo: z.string().nullable().optional(),
  taxCardNo: z.string().nullable().optional(),
  baseCurrencyCode: z.string().min(1).max(8).optional(),
  defaultTaxRate: z.number().min(0).max(100).optional(),
  taxEnabled: z.boolean().optional(),
  dashboardWidgets: z.string().nullable().optional(),
  invoicePrefix: z.string().min(1).max(8).optional(),
  salesOrderPrefix: z.string().min(1).max(8).optional(),
  purchaseOrderPrefix: z.string().min(1).max(8).optional(),
  paymentPrefix: z.string().min(1).max(8).optional(),
  journalPrefix: z.string().min(1).max(8).optional(),
  expensePrefix: z.string().min(1).max(8).optional(),
  openingBalancePrefix: z.string().min(1).max(8).optional(),
  lowStockAlerts: z.boolean().optional(),
});

router.get(
  '/',
  requirePermission('settings.read'),
  asyncHandler(async (_req, res) => {
    ok(res, await getSettings());
  }),
);

router.patch(
  '/',
  requirePermission('settings.write'),
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    await getSettings(); // ensure the row exists
    await prisma.setting.update({ where: { id: 1 }, data: req.body });
    invalidateSettingsCache();
    ok(res, await getSettings());
  }),
);

export default router;
