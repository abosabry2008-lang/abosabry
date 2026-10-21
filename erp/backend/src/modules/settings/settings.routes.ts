import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, ok } from '../../lib/http';
import {
  ALL_PERMISSIONS,
  ROLE_PERMISSIONS,
  parseCustomPermissions,
  rolePermissionOverrides,
  rolePermissions,
  setRolePermissionOverrides,
} from '../../lib/permissions';
import { prisma } from '../../lib/prisma';
import { getSettings, invalidateSettingsCache } from '../../lib/settings';
import { authenticate } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';

const router = Router();
router.use(authenticate);

const EDITABLE_ROLES = ['MANAGER', 'SALES', 'CASHIER', 'WAREHOUSE', 'ACCOUNTANT'] as const;

const rolePermissionsSchema = z.object({
  role: z.enum(EDITABLE_ROLES),
  permissions: z.array(z.string()),
});

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
  settlementPrefix: z.string().min(1).max(8).optional(),
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

/** Catalogue of every permission key plus the current role grants. */
router.get(
  '/role-permissions',
  requirePermission('roles.manage'),
  asyncHandler(async (_req, res) => {
    await getSettings();
    const roles = EDITABLE_ROLES.map((role) => ({
      role,
      permissions: rolePermissions(role),
    }));
    ok(res, { allPermissions: [...ALL_PERMISSIONS], roles });
  }),
);

/** Replaces one role's permission list (stored as a live override). */
router.put(
  '/role-permissions',
  requirePermission('roles.manage'),
  validateBody(rolePermissionsSchema),
  asyncHandler(async (req, res) => {
    const role = req.body.role as (typeof EDITABLE_ROLES)[number];
    const permissions = parseCustomPermissions(req.body.permissions).filter((p) =>
      (ALL_PERMISSIONS as readonly string[]).includes(p),
    );

    const current = rolePermissionOverrides();
    const next = { ...current, [role]: permissions };

    await getSettings(); // ensure the row exists
    await prisma.setting.update({
      where: { id: 1 },
      data: { rolePermissions: next as any },
    });
    setRolePermissionOverrides(next);
    invalidateSettingsCache();
    setRolePermissionOverrides(next); // re-apply after cache clear
    ok(res, { role, permissions: rolePermissions(role) });
  }),
);

/** Restores a role to its built-in default permission list. */
router.delete(
  '/role-permissions/:role',
  requirePermission('roles.manage'),
  asyncHandler(async (req, res) => {
    const role = String(req.params.role) as (typeof EDITABLE_ROLES)[number];
    if (!EDITABLE_ROLES.includes(role as any)) {
      ok(res, { role, permissions: [] });
      return;
    }
    const current = rolePermissionOverrides();
    delete current[role];
    await getSettings();
    await prisma.setting.update({
      where: { id: 1 },
      data: { rolePermissions: Object.keys(current).length ? (current as any) : null },
    });
    setRolePermissionOverrides(current);
    invalidateSettingsCache();
    setRolePermissionOverrides(current);
    ok(res, { role, permissions: rolePermissions(role), defaults: ROLE_PERMISSIONS[role] });
  }),
);

export default router;
