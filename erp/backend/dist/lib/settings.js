"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getSettings = getSettings;
exports.isTaxEnabled = isTaxEnabled;
exports.invalidateSettingsCache = invalidateSettingsCache;
exports.ensureRolePermissionsLoaded = ensureRolePermissionsLoaded;
const permissions_1 = require("./permissions");
const prisma_1 = require("../lib/prisma");
/** Returns the single settings row, creating defaults on first access. */
async function getSettings(client = prisma_1.prisma) {
    const existing = await client.setting.findUnique({ where: { id: 1 } });
    if (existing) {
        (0, permissions_1.setRolePermissionOverrides)(existing.rolePermissions);
        return {
            id: existing.id,
            companyName: existing.companyName,
            companyEmail: existing.companyEmail,
            companyPhone: existing.companyPhone,
            companyAddress: existing.companyAddress,
            logoUrl: existing.logoUrl,
            commercialRegisterNo: existing.commercialRegisterNo,
            taxCardNo: existing.taxCardNo,
            baseCurrencyCode: existing.baseCurrencyCode,
            defaultTaxRate: Number(existing.defaultTaxRate),
            taxEnabled: existing.taxEnabled,
            dashboardWidgets: existing.dashboardWidgets,
            rolePermissions: existing.rolePermissions ?? null,
            invoicePrefix: existing.invoicePrefix,
            salesOrderPrefix: existing.salesOrderPrefix,
            purchaseOrderPrefix: existing.purchaseOrderPrefix,
            paymentPrefix: existing.paymentPrefix,
            journalPrefix: existing.journalPrefix,
            expensePrefix: existing.expensePrefix,
            settlementPrefix: existing.settlementPrefix,
            openingBalancePrefix: existing.openingBalancePrefix,
            lowStockAlerts: existing.lowStockAlerts,
        };
    }
    const settings = await client.setting.create({ data: { id: 1 } });
    (0, permissions_1.setRolePermissionOverrides)(settings.rolePermissions);
    return {
        id: settings.id,
        companyName: settings.companyName,
        companyEmail: settings.companyEmail,
        companyPhone: settings.companyPhone,
        companyAddress: settings.companyAddress,
        logoUrl: settings.logoUrl,
        commercialRegisterNo: settings.commercialRegisterNo,
        taxCardNo: settings.taxCardNo,
        baseCurrencyCode: settings.baseCurrencyCode,
        defaultTaxRate: Number(settings.defaultTaxRate),
        taxEnabled: settings.taxEnabled,
        dashboardWidgets: settings.dashboardWidgets,
        rolePermissions: settings.rolePermissions ?? null,
        invoicePrefix: settings.invoicePrefix,
        salesOrderPrefix: settings.salesOrderPrefix,
        purchaseOrderPrefix: settings.purchaseOrderPrefix,
        paymentPrefix: settings.paymentPrefix,
        journalPrefix: settings.journalPrefix,
        expensePrefix: settings.expensePrefix,
        settlementPrefix: settings.settlementPrefix,
        openingBalancePrefix: settings.openingBalancePrefix,
        lowStockAlerts: settings.lowStockAlerts,
    };
}
let taxEnabledCache = null;
/**
 * Whether tax is currently enabled. Cached because it is read on every
 * document write; the cache is cleared whenever settings are updated.
 */
async function isTaxEnabled() {
    if (taxEnabledCache === null) {
        taxEnabledCache = (await getSettings()).taxEnabled;
    }
    return taxEnabledCache;
}
/** Clears cached settings-derived flags (call after a settings update). */
function invalidateSettingsCache() {
    taxEnabledCache = null;
    settingsLoaded = false;
}
let settingsLoaded = false;
/**
 * Makes sure the role-permission overrides are loaded into memory before the
 * first permission check. Safe to call repeatedly; only hits the DB once.
 */
async function ensureRolePermissionsLoaded() {
    if (settingsLoaded)
        return;
    settingsLoaded = true;
    try {
        await getSettings();
    }
    catch {
        settingsLoaded = false;
    }
}
//# sourceMappingURL=settings.js.map