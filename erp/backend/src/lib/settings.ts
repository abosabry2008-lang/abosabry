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
  invoicePrefix: string;
  salesOrderPrefix: string;
  purchaseOrderPrefix: string;
  paymentPrefix: string;
  journalPrefix: string;
  lowStockAlerts: boolean;
}

type Client = Tx | typeof prisma;

/** Returns the single settings row, creating defaults on first access. */
export async function getSettings(client: Client = prisma): Promise<AppSettings> {
  const existing = await client.setting.findUnique({ where: { id: 1 } });
  if (existing) {
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
      invoicePrefix: existing.invoicePrefix,
      salesOrderPrefix: existing.salesOrderPrefix,
      purchaseOrderPrefix: existing.purchaseOrderPrefix,
      paymentPrefix: existing.paymentPrefix,
      journalPrefix: existing.journalPrefix,
      lowStockAlerts: existing.lowStockAlerts,
    };
  }

  const settings = await client.setting.create({ data: { id: 1 } });
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
    invoicePrefix: settings.invoicePrefix,
    salesOrderPrefix: settings.salesOrderPrefix,
    purchaseOrderPrefix: settings.purchaseOrderPrefix,
    paymentPrefix: settings.paymentPrefix,
    journalPrefix: settings.journalPrefix,
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
}
