"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const http_1 = require("../../lib/http");
const permissions_1 = require("../../lib/permissions");
const prisma_1 = require("../../lib/prisma");
const settings_1 = require("../../lib/settings");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const EDITABLE_ROLES = ['MANAGER', 'SALES', 'CASHIER', 'WAREHOUSE', 'ACCOUNTANT'];
const rolePermissionsSchema = zod_1.z.object({
    role: zod_1.z.enum(EDITABLE_ROLES),
    permissions: zod_1.z.array(zod_1.z.string()),
});
const updateSchema = zod_1.z.object({
    companyName: zod_1.z.string().min(1).optional(),
    companyEmail: zod_1.z.string().nullable().optional(),
    companyPhone: zod_1.z.string().nullable().optional(),
    companyAddress: zod_1.z.string().nullable().optional(),
    logoUrl: zod_1.z.string().url().nullable().optional().or(zod_1.z.literal('').nullable()),
    commercialRegisterNo: zod_1.z.string().nullable().optional(),
    taxCardNo: zod_1.z.string().nullable().optional(),
    baseCurrencyCode: zod_1.z.string().min(1).max(8).optional(),
    defaultTaxRate: zod_1.z.number().min(0).max(100).optional(),
    taxEnabled: zod_1.z.boolean().optional(),
    dashboardWidgets: zod_1.z.string().nullable().optional(),
    invoicePrefix: zod_1.z.string().min(1).max(8).optional(),
    salesOrderPrefix: zod_1.z.string().min(1).max(8).optional(),
    purchaseOrderPrefix: zod_1.z.string().min(1).max(8).optional(),
    paymentPrefix: zod_1.z.string().min(1).max(8).optional(),
    journalPrefix: zod_1.z.string().min(1).max(8).optional(),
    expensePrefix: zod_1.z.string().min(1).max(8).optional(),
    settlementPrefix: zod_1.z.string().min(1).max(8).optional(),
    openingBalancePrefix: zod_1.z.string().min(1).max(8).optional(),
    lowStockAlerts: zod_1.z.boolean().optional(),
});
router.get('/', (0, authorize_1.requirePermission)('settings.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    (0, http_1.ok)(res, await (0, settings_1.getSettings)());
}));
router.patch('/', (0, authorize_1.requirePermission)('settings.write'), (0, validate_1.validateBody)(updateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    await (0, settings_1.getSettings)(); // ensure the row exists
    await prisma_1.prisma.setting.update({ where: { id: 1 }, data: req.body });
    (0, settings_1.invalidateSettingsCache)();
    (0, http_1.ok)(res, await (0, settings_1.getSettings)());
}));
/** Catalogue of every permission key plus the current role grants. */
router.get('/role-permissions', (0, authorize_1.requirePermission)('roles.manage'), (0, http_1.asyncHandler)(async (_req, res) => {
    await (0, settings_1.getSettings)();
    const roles = EDITABLE_ROLES.map((role) => ({
        role,
        permissions: (0, permissions_1.rolePermissions)(role),
    }));
    (0, http_1.ok)(res, { allPermissions: [...permissions_1.ALL_PERMISSIONS], roles });
}));
/** Replaces one role's permission list (stored as a live override). */
router.put('/role-permissions', (0, authorize_1.requirePermission)('roles.manage'), (0, validate_1.validateBody)(rolePermissionsSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const role = req.body.role;
    const permissions = (0, permissions_1.parseCustomPermissions)(req.body.permissions).filter((p) => permissions_1.ALL_PERMISSIONS.includes(p));
    const current = (0, permissions_1.rolePermissionOverrides)();
    const next = { ...current, [role]: permissions };
    await (0, settings_1.getSettings)(); // ensure the row exists
    await prisma_1.prisma.setting.update({
        where: { id: 1 },
        data: { rolePermissions: next },
    });
    (0, permissions_1.setRolePermissionOverrides)(next);
    (0, settings_1.invalidateSettingsCache)();
    (0, permissions_1.setRolePermissionOverrides)(next); // re-apply after cache clear
    (0, http_1.ok)(res, { role, permissions: (0, permissions_1.rolePermissions)(role) });
}));
/** Restores a role to its built-in default permission list. */
router.delete('/role-permissions/:role', (0, authorize_1.requirePermission)('roles.manage'), (0, http_1.asyncHandler)(async (req, res) => {
    const role = String(req.params.role);
    if (!EDITABLE_ROLES.includes(role)) {
        (0, http_1.ok)(res, { role, permissions: [] });
        return;
    }
    const current = (0, permissions_1.rolePermissionOverrides)();
    delete current[role];
    await (0, settings_1.getSettings)();
    await prisma_1.prisma.setting.update({
        where: { id: 1 },
        data: { rolePermissions: Object.keys(current).length ? current : null },
    });
    (0, permissions_1.setRolePermissionOverrides)(current);
    (0, settings_1.invalidateSettingsCache)();
    (0, permissions_1.setRolePermissionOverrides)(current);
    (0, http_1.ok)(res, { role, permissions: (0, permissions_1.rolePermissions)(role), defaults: permissions_1.ROLE_PERMISSIONS[role] });
}));
exports.default = router;
//# sourceMappingURL=settings.routes.js.map