import { setRolePermissionOverrides } from './permissions';
import { prisma, type Tx } from '../lib/prisma';

export interface AppSettings {
  id: number;
  companyName: string;
  companyEmail: string | null;
  companyPhone: string | null;
  companyAddress: string | null;
  logoUrl: string | null;
  commercialRegisterNo: string | null;
  taxCardNo: string | null;
  baseCurrencyCode: string;
  defaultTaxRate: number;
  taxEnabled: boolean;
  /** JSON-encoded list of enabled dashboard section keys, or null for all. */
  dashboardWidgets: string | null;
  /** JSON map of role -> permission keys overriding the built-in defaults. */
  rolePermissions: unknown;
  invoicePrefix: string;
  salesOrderPrefix: string;
  purchaseOrderPrefix: string;
  paymentPrefix: string;
  journalPrefix: string;
  expensePrefix: string;
  settlementPrefix: string;
  openingBalancePrefix: string;
  transferPrefix?: string;
  collectionPrefix?: string;
  returnOrderPrefix?: string;
  lowStockAlerts: boolean;
}

type Client = Tx | typeof prisma;

/** Returns the single settings row, creating defaults on first access. */
export async function getSettings(client: Client = prisma): Promise<AppSettings> {
  const existing = await client.setting.findUnique({ where: { id: 1 } });
  if (existing) {
    setRolePermissionOverrides((existing as any).rolePermissions);
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
      rolePermissions: (existing as any).rolePermissions ?? null,
      invoicePrefix: existing.invoicePrefix,
      salesOrderPrefix: existing.salesOrderPrefix,
      purchaseOrderPrefix: existing.purchaseOrderPrefix,
      paymentPrefix: existing.paymentPrefix,
      journalPrefix: existing.journalPrefix,
      expensePrefix: existing.expensePrefix,
      settlementPrefix: existing.settlementPrefix,
      openingBalancePrefix: existing.openingBalancePrefix,
      transferPrefix: (existing as any).transferPrefix ?? 'TRF',
      collectionPrefix: (existing as any).collectionPrefix ?? 'COL',
      returnOrderPrefix: (existing as any).returnOrderPrefix ?? 'RET',
      lowStockAlerts: existing.lowStockAlerts,
    };
  }

  const settings = await client.setting.create({ data: { id: 1 } });
  setRolePermissionOverrides((settings as any).rolePermissions);
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
    rolePermissions: (settings as any).rolePermissions ?? null,
    invoicePrefix: settings.invoicePrefix,
    salesOrderPrefix: settings.salesOrderPrefix,
    purchaseOrderPrefix: settings.purchaseOrderPrefix,
    paymentPrefix: settings.paymentPrefix,
    journalPrefix: settings.journalPrefix,
    expensePrefix: settings.expensePrefix,
    settlementPrefix: settings.settlementPrefix,
    openingBalancePrefix: settings.openingBalancePrefix,
    transferPrefix: (settings as any).transferPrefix ?? 'TRF',
    collectionPrefix: (settings as any).collectionPrefix ?? 'COL',
    returnOrderPrefix: (settings as any).returnOrderPrefix ?? 'RET',
    lowStockAlerts: settings.lowStockAlerts,
  };
}

let taxEnabledCache: boolean | null = null;

/**
 * Whether tax is currently enabled. Cached because it is read on every
 * document write; the cache is cleared whenever settings are updated.
 */
export async function isTaxEnabled(): Promise<boolean> {
  if (taxEnabledCache === null) {
    taxEnabledCache = (await getSettings()).taxEnabled;
  }
  return taxEnabledCache;
}

/** Clears cached settings-derived flags (call after a settings update). */
export function invalidateSettingsCache(): void {
  taxEnabledCache = null;
  settingsLoaded = false;
}

let settingsLoaded = false;

/**
 * Makes sure the role-permission overrides are loaded into memory before the
 * first permission check. Safe to call repeatedly; only hits the DB once.
 */
export async function ensureRolePermissionsLoaded(): Promise<void> {
  if (settingsLoaded) return;
  settingsLoaded = true;
  try {
    await getSettings();
  } catch {
    settingsLoaded = false;
  }
}
