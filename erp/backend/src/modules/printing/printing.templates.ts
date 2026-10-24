import { Prisma } from '@prisma/client';
import { localDayKey, localStamp } from '../../lib/local-time';
import { lineTotals, num, round2 } from '../../lib/money';
import type { AppSettings } from '../../lib/settings';
import { invoiceInclude } from '../invoices/invoices.service';
import type {
  InventoryValuationReport,
  SalesReport,
  TopProductsReport,
} from '../reports/reports.service';
import type {
  ItemMovementReport,
  ReceivablesBySalespersonReport,
  StockBalanceReport,
  SupplierPayablesReport,
} from '../reports/analytics.service';
import type {
  CustomerStatement,
  StatementRow,
  StatementRowType,
  StatementTotals,
  SupplierStatement,
} from '../reports/statement.service';
import type {
  SalespersonCollectionsReport,
  ConsolidatedSalesNote,
  SalespersonCustomerDebt,
  SalespersonProfitReport,
  SalespersonStatement,
} from '../reports/salespeople.service';
import type { ShortagesReport } from '../reports/analytics.service';
import type { OrderFulfilmentReport } from '../reports/analytics.service';
import type { CollectionsByBoxReport } from '../reports/collections.service';
import type { BoxStatement } from '../treasury/treasury.service';
import type { buildExpenseReport } from '../expenses/expenses.service';

type ExpenseReport = Awaited<ReturnType<typeof buildExpenseReport>>;

type InvoiceWithRelations = Prisma.InvoiceGetPayload<{ include: typeof invoiceInclude }>;

// ---------------------------------------------------------------------------
// Small formatting / safety helpers
// ---------------------------------------------------------------------------

/** Escapes a value for safe interpolation into HTML text or attributes. */
export function escapeHtml(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Formats money with 2 decimals and thousands separators (no dependencies). */
export function formatMoney(value: unknown): string {
  const n = num(value);
  const negative = n < 0;
  const [whole, decimals] = Math.abs(n).toFixed(2).split('.');
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${negative ? '-' : ''}${grouped}.${decimals}`;
}

function money(value: unknown): string {
  return formatMoney(value);
}

/** Formats a Date / date string as YYYY-MM-DD in the user's local timezone. */
export function formatDate(value: unknown): string {
  if (value === null || value === undefined || value === '') return '';
  const date = value instanceof Date ? value : new Date(String(value));
  if (Number.isNaN(date.getTime())) return '';
  return localDayKey(date);
}

function timestamp(): string {
  return localStamp(new Date());
}

// ---------------------------------------------------------------------------
// Page shell
// ---------------------------------------------------------------------------

const STYLES = `
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 24px;
    background: #f1f5f9;
    color: #0f172a;
    font-family: "Segoe UI", Arial, Helvetica, sans-serif;
    font-size: 13px;
    line-height: 1.45;
  }
  .page {
    max-width: 900px;
    margin: 0 auto;
    background: #ffffff;
    padding: 32px 36px;
    border: 1px solid #e2e8f0;
    border-radius: 8px;
  }
  .doc-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 24px;
    border-bottom: 2px solid #0f172a;
    padding-bottom: 16px;
    margin-bottom: 20px;
  }
  .company h1 { margin: 0 0 6px; font-size: 22px; }
  .doc-title { text-align: right; }
  .doc-title h2 { margin: 0 0 4px; font-size: 18px; letter-spacing: 0.04em; text-transform: uppercase; }
  .muted { color: #64748b; }
  .center { text-align: center; }
  .num { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
  section.meta {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px 24px;
    margin: 0 0 20px;
    padding: 12px 16px;
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 6px;
  }
  section.meta .label { display: inline-block; min-width: 110px; color: #64748b; }
  section.meta .value { font-weight: 600; }
  section.panel.invoice-info { background: #f8fafc; }
  .invoice-info .info-row {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 6px 24px;
  }
  .invoice-info .info-row + .info-row {
    margin-top: 8px;
    padding-top: 8px;
    border-top: 1px dashed #e2e8f0;
  }
  .invoice-info .label { display: inline-block; min-width: 90px; color: #64748b; }
  .invoice-info .value { font-weight: 600; }
  section.panel {
    margin: 0 0 20px;
    padding: 12px 16px;
    border: 1px solid #e2e8f0;
    border-radius: 6px;
  }
  section.panel h3 {
    margin: 0 0 6px;
    font-size: 11px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: #64748b;
  }
  table.data { width: 100%; border-collapse: collapse; margin: 0 0 20px; }
  table.data.invoice-lines { table-layout: fixed; }
  table.data th, table.data td { border: 1px solid #e2e8f0; padding: 7px 6px; vertical-align: top; }
  table.data thead th {
    background: #0f172a;
    color: #ffffff;
    font-size: 10px;
    font-weight: 500;
    padding: 6px 5px;
    text-transform: uppercase;
    letter-spacing: 0.02em;
    text-align: start;
  }
  table.data thead th.num { text-align: right; }
  table.data tbody tr:nth-child(even) { background: #f8fafc; }
  table.data tr.total td { font-weight: 700; background: #e2e8f0; border-top: 2px solid #0f172a; }
  .totals-wrap { display: flex; justify-content: flex-end; margin-bottom: 20px; }
  table.totals { border-collapse: collapse; min-width: 320px; }
  table.totals th, table.totals td { padding: 6px 12px; border-bottom: 1px solid #e2e8f0; }
  table.totals th { text-align: left; font-weight: 500; color: #334155; }
  table.totals tr.grand th, table.totals tr.grand td { font-weight: 700; border-top: 2px solid #0f172a; }
  .doc-footer { margin-top: 24px; border-top: 1px solid #e2e8f0; padding-top: 10px; color: #94a3b8; font-size: 11px; }
  @media print {
    body { background: #ffffff; padding: 0; font-size: 12px; }
    .page { max-width: none; border: 0; border-radius: 0; padding: 0; }
    table.data thead th { background: #0f172a !important; color: #ffffff !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    table.data tr.total td { background: #e2e8f0 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .doc-footer { color: #94a3b8; }
    a { color: inherit; text-decoration: none; }
  }
  @page { margin: 14mm; }
`;

/** Tight table layout so long name lists fit more rows per printed page. */
const COMPACT_TABLE_CSS = `
  @page { margin: 8mm; }
  body { padding: 0; background: #ffffff; font-size: 12px; line-height: 1.25; }
  .page { max-width: none; width: auto; margin: 0; padding: 0; border: 0; border-radius: 0; }
  .doc-header { padding-bottom: 6px; margin-bottom: 8px; }
  .doc-title h2 { font-size: 15px; }
  section.meta { gap: 4px 14px; margin-bottom: 8px; padding: 6px 10px; font-size: 11px; }
  table.data { margin-bottom: 6px; }
  table.data th, table.data td { padding: 2px 6px; font-size: 13px; line-height: 1.2; }
  table.data thead th { padding: 3px 6px; font-size: 10px; }
  table.data tr { page-break-inside: avoid; break-inside: avoid; }
  table.data thead { display: table-header-group; }
  .doc-footer { margin-top: 8px; padding-top: 4px; font-size: 9px; }
`;

export interface PageOptions {
  title: string;
  company: AppSettings;
  subtitle?: string;
  body: string;
  /** Text direction of the page (`rtl` for Arabic). Defaults to `ltr`. */
  dir?: 'ltr' | 'rtl';
  /** Document language attribute. Defaults to `en`. */
  lang?: string;
  /**
   * Whether to print the company name, address and legal identifiers in the
   * header. Defaults to `true` (invoices and statements). Reports pass `false`
   * so they carry only the report title.
   */
  showCompanyDetails?: boolean;
  /** Extra CSS appended after the shared styles (used for A5 invoices). */
  extraCss?: string;
}

/** Wraps a document body in a self-contained, printable HTML page. */
export function renderPage({
  title,
  company,
  subtitle,
  body,
  dir = 'ltr',
  lang = 'en',
  showCompanyDetails = true,
  extraCss = '',
}: PageOptions): string {
  const companyName = escapeHtml(company.companyName || 'ERP');
  const contact: string[] = [];
  if (showCompanyDetails) {
    if (company.companyAddress) contact.push(`<div class="muted">${escapeHtml(company.companyAddress)}</div>`);
    if (company.companyPhone) contact.push(`<div class="muted">${escapeHtml(company.companyPhone)}</div>`);
    if (company.companyEmail) contact.push(`<div class="muted">${escapeHtml(company.companyEmail)}</div>`);
    // Legal identifiers shown on printed documents (invoice, statement, ...).
    if (company.commercialRegisterNo) {
      contact.push(
        `<div class="muted">السجل التجاري / Commercial register: ${escapeHtml(company.commercialRegisterNo)}</div>`,
      );
    }
    if (company.taxCardNo) {
      contact.push(
        `<div class="muted">البطاقة الضريبية / Tax card: ${escapeHtml(company.taxCardNo)}</div>`,
      );
    }
  }

  const companyBlock = showCompanyDetails
    ? `    <div class="company">
      <h1>${companyName}</h1>
      ${contact.join('\n      ')}
    </div>
`
    : '';

  return `<!doctype html>
<html lang="${escapeHtml(lang)}" dir="${dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>${STYLES}${extraCss}</style>
</head>
<body>
<div class="page">
  <header class="doc-header">
${companyBlock}    <div class="doc-title">
      <h2>${escapeHtml(title)}</h2>
      ${subtitle ? `<div class="muted">${escapeHtml(subtitle)}</div>` : ''}
    </div>
  </header>
  <main>
${body}
  </main>
  <footer class="doc-footer">Generated ${escapeHtml(timestamp())}</footer>
</div>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// Invoice document
// ---------------------------------------------------------------------------

export function invoiceHtml(
  invoice: InvoiceWithRelations,
  settings: AppSettings,
  options: { previousBalance?: number; lang?: string; size?: 'a4' | 'a5' } = {},
): string {
  const ar = (options.lang ?? 'en') === 'ar';
  const t = (en: string, arabic: string) => (ar ? arabic : en);

  // What the customer already owed before this invoice (open balance on their
  // other documents plus any opening balance).
  const previousBalance = round2(Number(options.previousBalance ?? 0));

  const lineRows = invoice.lines
    .map((line, index) => {
      return `      <tr>
        <td class="num">${index + 1}</td>
        <td>${escapeHtml(line.description)}</td>
        <td class="num">${escapeHtml(line.quantity)}</td>
        <td class="num">${money(line.unitPrice)}</td>
        <td class="num">${money(line.total)}</td>
      </tr>`;
    })
    .join('\n');

  const customer = invoice.customer;
  // The customer's assigned rep wins; otherwise the sales user who issued the
  // invoice is shown so walk-in invoices still carry the salesperson details.
  const orderUser = invoice.salesOrder?.user;
  const salesperson =
    customer?.salesperson ?? (orderUser?.role === 'SALES' ? orderUser : null);
  const salespersonText = salesperson
    ? `${escapeHtml(salesperson.name)}${salesperson.phone ? ` · ${escapeHtml(salesperson.phone)}` : ''}`
    : '';
  const customerName = customer
    ? escapeHtml(customer.name)
    : escapeHtml(t('Walk-in customer', 'عميل نقدي'));
  const customerContact = customer
    ? [customer.phone, customer.address, customer.email]
        .filter((value): value is string => Boolean(value))
        .map((value) => escapeHtml(value))
        .join(' · ')
    : '';

  const body = `    <section class="panel invoice-info">
      <div class="info-row">
        <div><span class="label">${escapeHtml(t('Invoice', 'فاتورة'))}</span><span class="value">${escapeHtml(invoice.number)}</span></div>
        <div><span class="label">${escapeHtml(t('Issue date', 'تاريخ الإصدار'))}</span><span class="value">${escapeHtml(formatDate(invoice.issueDate))}</span></div>
      </div>
      <div class="info-row">
        <div><span class="label">${escapeHtml(t('Customer', 'العميل'))}</span><span class="value">${customerName}</span>${customerContact ? `<span class="muted"> · ${customerContact}</span>` : ''}</div>
        ${salesperson ? `<div><span class="label">${escapeHtml(t('Salesperson', 'المندوب'))}</span><span class="value">${salespersonText}</span></div>` : '<div></div>'}
      </div>
    </section>
    <table class="data invoice-lines">
      <colgroup>
        <col style="width: 7%">
        <col style="width: 32%">
        <col style="width: 14%">
        <col style="width: 21%">
        <col style="width: 26%">
      </colgroup>
      <thead>
        <tr>
          <th class="num">${escapeHtml(t('No.', 'م'))}</th>
          <th>${escapeHtml(t('Item', 'الصنف'))}</th>
          <th class="num">${escapeHtml(t('Qty', 'الكمية'))}</th>
          <th class="num">${escapeHtml(t('Unit price', 'سعر الوحدة'))}</th>
          <th class="num">${escapeHtml(t('Line total', 'إجمالي السطر'))}</th>
        </tr>
      </thead>
      <tbody>
${lineRows || `        <tr><td colspan="5" class="muted center">${escapeHtml(t('No lines', 'لا توجد أصناف'))}</td></tr>`}
      </tbody>
    </table>
    <div class="totals-wrap">
      <table class="totals">
        <tbody>
          <tr class="grand"><th>${escapeHtml(t('Total', 'الإجمالي'))}</th><td class="num">${money(invoice.total)}</td></tr>
          <tr><th>${escapeHtml(t('Paid', 'المدفوع'))}</th><td class="num">${money(invoice.amountPaid)}</td></tr>${
            customer
              ? `
          <tr><th>${escapeHtml(t('Previous balance', 'الرصيد السابق'))}</th><td class="num">${money(previousBalance)}</td></tr>
          <tr class="grand"><th>${escapeHtml(t('Total due', 'إجمالي المديونية'))}</th><td class="num">${money(
            round2(previousBalance + Number(invoice.balance)),
          )}</td></tr>`
              : ''
          }
        </tbody>
      </table>
    </div>${
      invoice.notes
        ? `
    <section class="panel">
      <h3>${escapeHtml(t('Notes', 'ملاحظات'))}</h3>
      <div>${escapeHtml(invoice.notes)}</div>
    </section>`
        : ''
    }
`;

  const a5 = options.size === 'a5';
  const a5Css = a5
    ? `
  @page { size: A5; margin: 5mm; }
  body { padding: 0; background: #ffffff; font-size: 11.5px; line-height: 1.35; }
  .page { max-width: none; width: auto; margin: 0; padding: 0; border: 0; border-radius: 0; }
  .doc-header { padding-bottom: 8px; margin-bottom: 10px; gap: 12px; }
  .company h1 { font-size: 17px; }
  .company .muted { font-size: 9.5px; }
  .doc-title h2 { font-size: 15px; }
  section.panel { padding: 8px 10px; margin-bottom: 10px; }
  .invoice-info .info-row { gap: 4px 12px; }
  .invoice-info .info-row + .info-row { margin-top: 5px; padding-top: 5px; }
  .invoice-info .label { min-width: 68px; }
  table.data { margin-bottom: 10px; }
  table.data th, table.data td { padding: 4px 5px; font-size: 10.5px; }
  table.data thead th { padding: 4px 5px; font-size: 10px; }
  table.data tr { page-break-inside: avoid; break-inside: avoid; }
  table.data thead { display: table-header-group; }
  .totals-wrap { margin-bottom: 10px; }
  table.totals th, table.totals td { padding: 3px 8px; font-size: 11px; }
  .doc-footer { margin-top: 10px; padding-top: 6px; font-size: 9.5px; }
`
    : '';

  return renderPage({
    title: `${t('Invoice', 'فاتورة')} ${invoice.number}`,
    company: settings,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang: ar ? 'ar' : 'en',
    extraCss: a5Css,
  });
}

/** Daily hand-over pack: one A5 page per invoice for a salesperson. */
export function salespersonInvoicesHtml(
  invoices: InvoiceWithRelations[],
  settings: AppSettings,
  lang = 'en',
  salespersonName?: string | null,
  salespersonPhone?: string | null,
): string {
  const ar = isArabic(lang);
  const t = (en: string, arabic: string) => (ar ? arabic : en);
  const company = escapeHtml(settings.companyName || 'ERP');
  const pages = invoices
    .map((invoice) => {
      const rows = invoice.lines
        .map(
          (line, index) => `      <tr>
        <td class="num">${index + 1}</td>
        <td>${escapeHtml(line.description)}</td>
        <td class="num">${escapeHtml(line.quantity)}</td>
        <td class="num">${money(line.unitPrice)}</td>
        <td class="num">${money(line.total)}</td>
      </tr>`,
        )
        .join('\n');
      const customer = invoice.customer;
      return `  <section class="a5">
    <header class="a5-head">
      <div>
        <strong>${company}</strong>
        ${settings.companyPhone ? `<div class="muted">${escapeHtml(settings.companyPhone)}</div>` : ''}
      </div>
      <div class="a5-title">
        <h2>${escapeHtml(t('Sales invoice', 'فاتورة بيع'))}</h2>
        <div>${escapeHtml(invoice.number)}</div>
        <div class="muted">${escapeHtml(formatDate(invoice.issueDate))}</div>
      </div>
    </header>
    <div class="a5-customer">
      <span>${escapeHtml(t('Customer', 'العميل'))}:</span>
      <strong>${escapeHtml(customer?.name ?? t('Walk-in customer', 'عميل نقدي'))}</strong>
      ${customer?.phone ? `<span class="muted">${escapeHtml(customer.phone)}</span>` : ''}
      ${salespersonName ? `<span class="muted">${escapeHtml(t('Salesperson', 'المندوب'))}: ${escapeHtml(salespersonName)}${salespersonPhone ? ` · ${escapeHtml(salespersonPhone)}` : ''}</span>` : ''}
    </div>
    <table class="data a5-table">
      <thead><tr>
        <th class="num">${escapeHtml(t('No.', 'م'))}</th>
        <th>${escapeHtml(t('Item', 'الصنف'))}</th>
        <th class="num">${escapeHtml(t('Qty', 'الكمية'))}</th>
        <th class="num">${escapeHtml(t('Price', 'السعر'))}</th>
        <th class="num">${escapeHtml(t('Total', 'الإجمالي'))}</th>
      </tr></thead>
      <tbody>${rows || `<tr><td colspan="5" class="muted center">${escapeHtml(t('No lines', 'لا توجد أصناف'))}</td></tr>`}</tbody>
    </table>
    <table class="totals a5-totals">
      <tbody>
        <tr class="grand"><th>${escapeHtml(t('Total', 'الإجمالي'))}</th><td class="num">${money(invoice.total)}</td></tr>
        <tr><th>${escapeHtml(t('Paid', 'المدفوع'))}</th><td class="num">${money(invoice.amountPaid)}</td></tr>
      </tbody>
    </table>
    <div class="a5-sign">
      <span>${escapeHtml(t('Salesperson signature', 'توقيع المندوب'))}: ....................................</span>
      <span>${escapeHtml(t('Customer signature', 'توقيع العميل'))}: ....................................</span>
    </div>
  </section>`;
    })
    .join('\n');

  const extra = `
  @page { size: A5; margin: 5mm; }
  body { background: #fff; padding: 0; font-size: 12px; }
  .a5 { page-break-after: always; break-after: page; padding: 0; margin: 0; }
  .a5:last-child { page-break-after: auto; break-after: auto; }
  .a5-head { display: flex; justify-content: space-between; gap: 10px; border-bottom: 2px solid #0f172a; padding-bottom: 5px; margin-bottom: 6px; }
  .a5-head h2 { margin: 0; font-size: 15px; }
  .a5-title { text-align: ${ar ? 'left' : 'right'}; }
  .a5-customer { display: flex; flex-wrap: wrap; gap: 4px 12px; margin-bottom: 6px; padding: 4px 7px; background: #f8fafc; border: 1px solid #e2e8f0; }
  .a5-table th, .a5-table td { padding: 3px 5px; font-size: 11.5px; }
  .a5-table { margin-bottom: 6px; }
  .a5-totals { margin-${ar ? 'right' : 'left'}: auto; margin-bottom: 6px; min-width: 240px; }
  .a5-totals th, .a5-totals td { padding: 2px 8px; }
  .a5-sign { display: flex; justify-content: space-between; gap: 16px; margin-top: 8px; font-size: 10px; color: #475569; }
  @media print { body { padding: 0; } .a5 { padding: 0; } }
  `;

  return `<!doctype html>
<html lang="${ar ? 'ar' : 'en'}" dir="${ar ? 'rtl' : 'ltr'}">
<head><meta charset="utf-8"><title>${escapeHtml(t('Daily sales invoices', 'فواتير المبيعات اليومية'))}</title>
<style>${STYLES}${extra}</style></head>
<body>${pages}</body></html>`;
}

// ---------------------------------------------------------------------------
// Account statements
// ---------------------------------------------------------------------------

const ROW_TYPE_LABEL: Record<StatementRowType, string> = {
  INVOICE: 'Invoice',
  PAYMENT: 'Payment',
  PURCHASE_ORDER: 'Purchase order',
  RETURN: 'Return',
  SETTLEMENT: 'Settlement',
};

const ROW_TYPE_LABEL_AR: Record<StatementRowType, string> = {
  INVOICE: 'فاتورة',
  PAYMENT: 'سداد',
  PURCHASE_ORDER: 'أمر شراء',
  RETURN: 'مرتجع',
  SETTLEMENT: 'تسوية',
};

interface StatementView {
  from: string | null;
  to: string | null;
  openingBalance: number;
  rows: StatementRow[];
  totals: StatementTotals;
}

interface PartyInfo {
  heading: string;
  name: string;
  lines: (string | null)[];
}

function statementBody(view: StatementView, party: PartyInfo, lang = 'en'): string {
  const ar = lang === 'ar';
  const t = (en: string, arabic: string) => (ar ? arabic : en);
  const typeLabels = ar ? ROW_TYPE_LABEL_AR : ROW_TYPE_LABEL;

  const rows = view.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(formatDate(row.date))}</td>
        <td>${escapeHtml(typeLabels[row.type])}</td>
        <td>${escapeHtml(row.number)}</td>
        <td>${escapeHtml(row.description)}</td>
        <td class="num">${row.debit ? money(row.debit) : ''}</td>
        <td class="num">${row.credit ? money(row.credit) : ''}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`,
    )
    .join('\n');

  const contact = party.lines
    .filter((line): line is string => Boolean(line))
    .map((line) => `      <div class="muted">${escapeHtml(line)}</div>`)
    .join('\n');

  return `    <section class="meta">
      <div><span class="label">${escapeHtml(t('Account', 'الحساب'))}</span><span class="value">${escapeHtml(party.name)}</span></div>
      <div><span class="label">${escapeHtml(t('From', 'من'))}</span><span class="value">${escapeHtml(view.from ?? '—')}</span></div>
      <div><span class="label">${escapeHtml(t('To', 'إلى'))}</span><span class="value">${escapeHtml(view.to ?? '—')}</span></div>
      <div><span class="label">${escapeHtml(t('Opening balance', 'الرصيد الافتتاحي'))}</span><span class="value">${money(view.openingBalance)}</span></div>
    </section>
    <section class="panel">
      <h3>${escapeHtml(party.heading)}</h3>
      <div>${escapeHtml(party.name)}</div>
${contact}
    </section>
    <table class="data">
      <thead>
        <tr>
          <th>${escapeHtml(t('Date', 'التاريخ'))}</th>
          <th>${escapeHtml(t('Type', 'النوع'))}</th>
          <th>${escapeHtml(t('Number', 'رقم المستند'))}</th>
          <th>${escapeHtml(t('Description', 'البيان'))}</th>
          <th class="num">${escapeHtml(t('Debit', 'مدين'))}</th>
          <th class="num">${escapeHtml(t('Credit', 'دائن'))}</th>
          <th class="num">${escapeHtml(t('Balance', 'الرصيد'))}</th>
        </tr>
      </thead>
      <tbody>
        <tr class="muted"><td colspan="6">${escapeHtml(t('Opening balance', 'الرصيد الافتتاحي'))}</td><td class="num">${money(view.openingBalance)}</td></tr>
${rows || `        <tr><td colspan="7" class="muted center">${escapeHtml(t('No transactions in this period', 'لا توجد حركات في هذه الفترة'))}</td></tr>`}
        <tr class="total"><td colspan="4">${escapeHtml(t('Totals', 'الإجماليات'))}</td><td class="num">${money(view.totals.debit)}</td><td class="num">${money(view.totals.credit)}</td><td class="num">${money(view.totals.closingBalance)}</td></tr>
      </tbody>
    </table>`;
}

export function customerStatementHtml(
  statement: CustomerStatement,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = lang === 'ar';
  const body = statementBody(
    statement,
    {
      heading: ar ? 'العميل' : 'Customer',
      name: statement.customer.name,
      lines: [statement.customer.address, statement.customer.email, statement.customer.phone],
    },
    lang,
  );
  return renderPage({
    title: ar ? 'كشف حساب عميل' : 'Customer statement',
    company: settings,
    subtitle: statement.customer.name,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang: ar ? 'ar' : 'en',
  });
}

export function supplierStatementHtml(
  statement: SupplierStatement,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = lang === 'ar';
  const body = statementBody(
    statement,
    {
      heading: ar ? 'المورد' : 'Supplier',
      name: statement.supplier.name,
      lines: [statement.supplier.address, statement.supplier.email, statement.supplier.phone],
    },
    lang,
  );
  return renderPage({
    title: ar ? 'كشف حساب مورد' : 'Supplier statement',
    company: settings,
    subtitle: statement.supplier.name,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang: ar ? 'ar' : 'en',
  });
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

export function salesReportHtml(report: SalesReport, settings: AppSettings): string {
  const rows = report.series
    .map(
      (bucket) => `      <tr>
        <td>${escapeHtml(bucket.period)}</td>
        <td class="num">${escapeHtml(bucket.orders)}</td>
        <td class="num">${money(bucket.subtotal)}</td>
        <td class="num">${money(bucket.discount)}</td>
        <td class="num">${money(bucket.tax)}</td>
        <td class="num">${money(bucket.total)}</td>
      </tr>`,
    )
    .join('\n');

  const body = `    <section class="meta">
      <div><span class="label">From</span><span class="value">${escapeHtml(report.from)}</span></div>
      <div><span class="label">To</span><span class="value">${escapeHtml(report.to)}</span></div>
      <div><span class="label">Group by</span><span class="value">${escapeHtml(report.groupBy)}</span></div>
    </section>
    <table class="data">
      <thead>
        <tr>
          <th>Period</th>
          <th class="num">Orders</th>
          <th class="num">Subtotal</th>
          <th class="num">Discount</th>
          <th class="num">Tax</th>
          <th class="num">Total</th>
        </tr>
      </thead>
      <tbody>
${rows || '        <tr><td colspan="6" class="muted center">No sales in this period</td></tr>'}
        <tr class="total"><td>Totals</td><td class="num">${escapeHtml(report.totals.orders)}</td><td class="num">${money(report.totals.subtotal)}</td><td class="num">${money(report.totals.discount)}</td><td class="num">${money(report.totals.tax)}</td><td class="num">${money(report.totals.total)}</td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: 'Sales report',
    company: settings,
    showCompanyDetails: false,
    subtitle: `${report.from} to ${report.to}`,
    body,
  });
}

export function inventoryValuationHtml(report: InventoryValuationReport, settings: AppSettings): string {
  const rows = report.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(row.sku)}</td>
        <td>${escapeHtml(row.name)}</td>
        <td>${escapeHtml(row.warehouse.name)}</td>
        <td>${escapeHtml(row.location.name ?? row.location.code)}</td>
        <td class="num">${escapeHtml(row.quantity)}</td>
        <td class="num">${money(row.unitCost)}</td>
        <td class="num">${money(row.costValue)}</td>
        <td class="num">${money(row.unitPrice)}</td>
        <td class="num">${money(row.retailValue)}</td>
      </tr>`,
    )
    .join('\n');

  const body = `    <table class="data">
      <thead>
        <tr>
          <th>SKU</th>
          <th>Product</th>
          <th>Warehouse</th>
          <th>Location</th>
          <th class="num">Qty</th>
          <th class="num">Unit cost</th>
          <th class="num">Cost value</th>
          <th class="num">Unit price</th>
          <th class="num">Retail value</th>
        </tr>
      </thead>
      <tbody>
${rows || '        <tr><td colspan="9" class="muted center">No stock on hand</td></tr>'}
        <tr class="total"><td colspan="4">Totals</td><td class="num">${escapeHtml(report.totals.units)}</td><td></td><td class="num">${money(report.totals.costValue)}</td><td></td><td class="num">${money(report.totals.retailValue)}</td></tr>
      </tbody>
    </table>`;

  return renderPage({ title: 'Inventory valuation', company: settings, body, showCompanyDetails: false });
}

export function topProductsHtml(report: TopProductsReport, settings: AppSettings): string {
  const rows = report.rows
    .map(
      (row, index) => `      <tr>
        <td class="num">${index + 1}</td>
        <td>${escapeHtml(row.sku)}</td>
        <td>${escapeHtml(row.name)}</td>
        <td class="num">${escapeHtml(row.quantitySold)}</td>
        <td class="num">${escapeHtml(row.orders)}</td>
        <td class="num">${money(row.revenue)}</td>
      </tr>`,
    )
    .join('\n');

  const body = `    <section class="meta">
      <div><span class="label">From</span><span class="value">${escapeHtml(report.from)}</span></div>
      <div><span class="label">To</span><span class="value">${escapeHtml(report.to)}</span></div>
    </section>
    <table class="data">
      <thead>
        <tr>
          <th class="num">#</th>
          <th>SKU</th>
          <th>Product</th>
          <th class="num">Qty sold</th>
          <th class="num">Orders</th>
          <th class="num">Revenue</th>
        </tr>
      </thead>
      <tbody>
${rows || '        <tr><td colspan="6" class="muted center">No sales in this period</td></tr>'}
      </tbody>
    </table>`;

  return renderPage({
    title: 'Top products',
    company: settings,
    showCompanyDetails: false,
    subtitle: `${report.from} to ${report.to}`,
    body,
  });
}

// ---------------------------------------------------------------------------
// Extended reports (bilingual: English / Arabic)
// ---------------------------------------------------------------------------

const isArabic = (lang: string): boolean => lang === 'ar';

const rangeLabel = (report: { from: string | null; to: string | null }): string | undefined =>
  report.from && report.to ? `${formatDate(report.from)} - ${formatDate(report.to)}` : undefined;

export function receivablesBySalespersonHtml(
  report: ReceivablesBySalespersonReport,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = report.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(row.salesperson ?? (ar ? 'بدون مندوب' : 'Unassigned'))}</td>
        <td>${escapeHtml(row.customer ?? '—')}</td>
        <td class="num">${escapeHtml(row.invoices)}</td>
        <td class="num">${money(row.total)}</td>
        <td class="num">${money(row.paid)}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا توجد أرصدة مستحقة' : 'No outstanding balances';

  const body = `    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'المندوب' : 'Salesperson'}</th>
          <th>${ar ? 'العميل' : 'Customer'}</th>
          <th class="num">${ar ? 'الفواتير' : 'Invoices'}</th>
          <th class="num">${ar ? 'الإجمالي' : 'Total'}</th>
          <th class="num">${ar ? 'المدفوع' : 'Paid'}</th>
          <th class="num">${ar ? 'المستحق' : 'Balance'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="6" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td colspan="2">${ar ? 'الإجمالي' : 'Totals'}</td><td class="num">${escapeHtml(report.totals.invoices)}</td><td class="num">${money(report.totals.total)}</td><td class="num">${money(report.totals.paid)}</td><td class="num">${money(report.totals.balance)}</td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? 'مديونية العملاء لكل مندوب' : 'Receivables by salesperson',
    company: settings,
    showCompanyDetails: false,
    subtitle: rangeLabel(report),
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
    extraCss: COMPACT_TABLE_CSS,
  });
}

export function supplierPayablesHtml(
  report: SupplierPayablesReport,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = report.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(row.supplier)}</td>
        <td>${escapeHtml(row.phone ?? '—')}</td>
        <td class="num">${escapeHtml(row.purchaseOrders)}</td>
        <td class="num">${money(row.purchases)}</td>
        <td class="num">${money(row.paid)}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا توجد مستحقات' : 'No payables';

  const body = `    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'المورد' : 'Supplier'}</th>
          <th>${ar ? 'الهاتف' : 'Phone'}</th>
          <th class="num">${ar ? 'أوامر الشراء' : 'POs'}</th>
          <th class="num">${ar ? 'المشتريات' : 'Purchases'}</th>
          <th class="num">${ar ? 'المدفوع' : 'Paid'}</th>
          <th class="num">${ar ? 'المستحق' : 'Balance'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="6" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td colspan="2">${ar ? 'الإجمالي' : 'Totals'}</td><td class="num">${escapeHtml(report.totals.purchaseOrders)}</td><td class="num">${money(report.totals.purchases)}</td><td class="num">${money(report.totals.paid)}</td><td class="num">${money(report.totals.balance)}</td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? 'مديونية الموردين' : 'Supplier payables',
    company: settings,
    showCompanyDetails: false,
    subtitle: rangeLabel(report),
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

export function stockBalanceHtml(
  report: StockBalanceReport,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = report.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(row.sku)}</td>
        <td>${escapeHtml(row.name)}</td>
        <td>${escapeHtml(row.category ?? '—')}</td>
        <td>${escapeHtml(row.warehouse)}</td>
        <td class="num">${escapeHtml(row.quantity)}</td>
        <td class="num">${escapeHtml(row.reserved)}</td>
        <td class="num">${escapeHtml(row.available)}</td>
        <td class="num">${money(row.unitCost)}</td>
        <td class="num">${money(row.costValue)}</td>
        <td class="num">${money(row.retailValue)}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا يوجد رصيد في المخزون' : 'No stock on hand';

  const body = `    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'الكود' : 'SKU'}</th>
          <th>${ar ? 'الصنف' : 'Product'}</th>
          <th>${ar ? 'الفئة' : 'Category'}</th>
          <th>${ar ? 'المستودع' : 'Warehouse'}</th>
          <th class="num">${ar ? 'الكمية' : 'Qty'}</th>
          <th class="num">${ar ? 'المحجوز' : 'Reserved'}</th>
          <th class="num">${ar ? 'المتاح' : 'Available'}</th>
          <th class="num">${ar ? 'تكلفة الوحدة' : 'Unit cost'}</th>
          <th class="num">${ar ? 'قيمة التكلفة' : 'Cost value'}</th>
          <th class="num">${ar ? 'قيمة البيع' : 'Retail value'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="10" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td colspan="4">${ar ? 'الإجمالي' : 'Totals'}</td><td class="num">${escapeHtml(report.totals.quantity)}</td><td></td><td class="num">${escapeHtml(report.totals.available)}</td><td></td><td class="num">${money(report.totals.costValue)}</td><td class="num">${money(report.totals.retailValue)}</td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? 'رصيد المخزون (كمية وقيمة)' : 'Stock balance (quantity & value)',
    company: settings,
    showCompanyDetails: false,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

export function itemMovementHtml(
  report: ItemMovementReport,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = report.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(formatDate(row.date))}</td>
        <td>${escapeHtml(row.type)}</td>
        <td>${escapeHtml(row.reference ?? '—')}</td>
        <td>${escapeHtml(
          row.party
            ? row.party.type === 'CASH'
              ? ar
                ? 'بيع نقدي'
                : 'Cash sale'
              : row.party.type === 'CUSTOMER'
                ? `${ar ? (row.dir === 'IN' ? 'من العميل' : 'إلى العميل') : row.dir === 'IN' ? 'From customer' : 'To customer'}: ${row.party.name ?? '—'}`
                : `${ar ? (row.dir === 'IN' ? 'من المورد' : 'إلى المورد') : row.dir === 'IN' ? 'From supplier' : 'To supplier'}: ${row.party.name ?? '—'}`
            : '—',
        )}</td>
        <td>${escapeHtml(row.warehouse ?? '—')}</td>
        <td>${escapeHtml(row.location ?? '—')}</td>
        <td class="num">${row.in ? escapeHtml(row.in) : ''}</td>
        <td class="num">${row.out ? escapeHtml(row.out) : ''}</td>
        <td class="num">${escapeHtml(row.balance)}</td>
        <td class="num">${money(row.unitCost)}</td>
        <td class="num">${money(row.value)}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا توجد حركات في هذه الفترة' : 'No movements in this period';

  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'الصنف' : 'Product'}</span><span class="value">${escapeHtml(report.product.name)} (${escapeHtml(report.product.sku)})</span></div>
      <div><span class="label">${ar ? 'الرصيد الافتتاحي' : 'Opening'}</span><span class="value">${escapeHtml(report.opening.quantity)} · ${money(report.opening.value)}</span></div>
    </table>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'التاريخ' : 'Date'}</th>
          <th>${ar ? 'النوع' : 'Type'}</th>
          <th>${ar ? 'المرجع' : 'Reference'}</th>
          <th>${ar ? 'الجهة' : 'Party'}</th>
          <th>${ar ? 'المستودع' : 'Warehouse'}</th>
          <th>${ar ? 'الموقع' : 'Location'}</th>
          <th class="num">${ar ? 'وارد' : 'In'}</th>
          <th class="num">${ar ? 'منصرف' : 'Out'}</th>
          <th class="num">${ar ? 'الرصيد' : 'Balance'}</th>
          <th class="num">${ar ? 'تكلفة الوحدة' : 'Unit cost'}</th>
          <th class="num">${ar ? 'القيمة' : 'Value'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="11" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td colspan="6">${ar ? 'الإجمالي' : 'Totals'}</td><td class="num">${escapeHtml(report.totals.inQty)}</td><td class="num">${escapeHtml(report.totals.outQty)}</td><td class="num">${escapeHtml(report.totals.closingQty)}</td><td></td><td class="num">${money(report.totals.closingValue)}</td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? 'حركة صنف' : 'Item movement',
    company: settings,
    showCompanyDetails: false,
    subtitle: `${report.product.name} (${report.product.sku})`,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

// ---------------------------------------------------------------------------
// Salespeople reports (تقارير المناديب)
// ---------------------------------------------------------------------------

export function consolidatedSalesNoteHtml(
  report: ConsolidatedSalesNote,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const unassigned = ar ? 'بدون مندوب' : 'Unassigned';

  const sections = report.rows
    .map((rep) => {
      const rows = rep.lines
        .map(
          (line) => `      <tr>
        <td>${escapeHtml(line.sku)}</td>
        <td>${escapeHtml(line.name)}</td>
        <td>${escapeHtml(line.unit)}</td>
        <td class="num">${escapeHtml(line.quantity)}</td>
        <td class="num">${money(line.net)}</td>
      </tr>`,
        )
        .join('\n');
      return `    <h3>${escapeHtml(rep.salesperson ?? unassigned)}</h3>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'الكود' : 'SKU'}</th>
          <th>${ar ? 'الصنف' : 'Product'}</th>
          <th>${ar ? 'الوحدة' : 'Unit'}</th>
          <th class="num">${ar ? 'الكمية' : 'Quantity'}</th>
          <th class="num">${ar ? 'صافي المبيعات' : 'Net sales'}</th>
        </tr>
      </thead>
      <tbody>
${rows}
        <tr class="total"><td colspan="3">${ar ? 'إجمالي المندوب' : 'Salesperson total'}</td><td class="num">${escapeHtml(rep.quantity)}</td><td class="num">${money(rep.net)}</td></tr>
      </tbody>
    </table>`;
    })
    .join('\n');

  const empty = ar ? 'لا مبيعات في هذه الفترة' : 'No sales in this period';
  const body = sections || `    <p class="muted center">${empty}</p>`;

  return renderPage({
    title: ar ? 'الإذن المجمع للمبيعات' : 'Consolidated sales note',
    company: settings,
    showCompanyDetails: false,
    subtitle: rangeLabel(report),
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

export function profitBySalespersonHtml(
  report: SalespersonProfitReport,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = report.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(row.salesperson ?? (ar ? 'بدون مندوب' : 'Unassigned'))}</td>
        <td class="num">${escapeHtml(row.orders)}</td>
        <td class="num">${money(row.revenue)}</td>
        <td class="num">${money(row.cost)}</td>
        <td class="num">${money(row.profit)}</td>
        <td class="num">${escapeHtml(row.margin)}%</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا مبيعات في هذه الفترة' : 'No sales in this period';

  const body = `    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'المندوب' : 'Salesperson'}</th>
          <th class="num">${ar ? 'الأوامر' : 'Orders'}</th>
          <th class="num">${ar ? 'الإيراد' : 'Revenue'}</th>
          <th class="num">${ar ? 'التكلفة' : 'Cost'}</th>
          <th class="num">${ar ? 'الربح' : 'Profit'}</th>
          <th class="num">${ar ? 'الهامش' : 'Margin'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="6" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td>${ar ? 'الإجمالي' : 'Totals'}</td><td></td><td class="num">${money(report.totals.revenue)}</td><td class="num">${money(report.totals.cost)}</td><td class="num">${money(report.totals.profit)}</td><td class="num">${escapeHtml(report.totals.margin)}%</td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? 'ربحية كل مندوب' : 'Profitability by salesperson',
    company: settings,
    showCompanyDetails: false,
    subtitle: rangeLabel(report),
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

export function collectionsBySalespersonHtml(
  report: SalespersonCollectionsReport,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = report.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(row.salesperson ?? (ar ? 'بدون مندوب' : 'Unassigned'))}</td>
        <td class="num">${escapeHtml(row.vouchers)}</td>
        <td class="num">${money(row.amount)}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا تحصيلات في هذه الفترة' : 'No collections in this period';

  const body = `    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'المندوب' : 'Salesperson'}</th>
          <th class="num">${ar ? 'الإيصالات' : 'Receipts'}</th>
          <th class="num">${ar ? 'المحصّل' : 'Collected'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="3" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td>${ar ? 'الإجمالي' : 'Totals'}</td><td class="num">${escapeHtml(report.totals.vouchers)}</td><td class="num">${money(report.totals.amount)}</td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? 'تحصيلات كل مندوب' : 'Collections by salesperson',
    company: settings,
    showCompanyDetails: false,
    subtitle: rangeLabel(report),
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

export function salespersonStatementHtml(
  statement: SalespersonStatement,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = statement.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(formatDate(row.date))}</td>
        <td>${escapeHtml(row.type === 'SALE' ? (ar ? 'فاتورة' : 'Invoice') : ar ? 'تحصيل' : 'Collection')}</td>
        <td>${escapeHtml(row.reference)}</td>
        <td>${escapeHtml(row.customer ?? '—')}</td>
        <td class="num">${row.debit ? money(row.debit) : ''}</td>
        <td class="num">${row.credit ? money(row.credit) : ''}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا حركات في هذه الفترة' : 'No movements in this period';

  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'الرصيد الافتتاحي' : 'Opening balance'}</span><span class="value">${money(statement.openingBalance)}</span></div>
      <div><span class="label">${ar ? 'الرصيد الختامي' : 'Closing balance'}</span><span class="value">${money(statement.totals.closingBalance)}</span></div>
    </section>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'التاريخ' : 'Date'}</th>
          <th>${ar ? 'النوع' : 'Type'}</th>
          <th>${ar ? 'المرجع' : 'Reference'}</th>
          <th>${ar ? 'العميل' : 'Customer'}</th>
          <th class="num">${ar ? 'مدين' : 'Debit'}</th>
          <th class="num">${ar ? 'دائن' : 'Credit'}</th>
          <th class="num">${ar ? 'الرصيد' : 'Balance'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="7" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td colspan="4">${ar ? 'الإجمالي' : 'Totals'}</td><td class="num">${money(statement.totals.sales)}</td><td class="num">${money(statement.totals.collections)}</td><td class="num">${money(statement.totals.closingBalance)}</td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? 'كشف حساب مندوب' : 'Salesperson statement',
    company: settings,
    showCompanyDetails: false,
    subtitle: `${statement.salesperson.name} · ${statement.from} → ${statement.to}`,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

export function expenseReportHtml(
  report: ExpenseReport,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const catRows = report.categories
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(row.name)}</td>
        <td class="num">${escapeHtml(row.count)}</td>
        <td class="num">${money(row.amount)}</td>
      </tr>`,
    )
    .join('\n');
  const monthRows = report.months
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(row.month)}</td>
        <td class="num">${money(row.amount)}</td>
      </tr>`,
    )
    .join('\n');
  const boxRows = report.boxes
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(row.name)}</td>
        <td class="num">${money(row.amount)}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا مصروفات في هذه الفترة' : 'No expenses in this period';

  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'عدد المصروفات' : 'Expenses'}</span><span class="value">${escapeHtml(report.count)}</span></div>
      <div><span class="label">${ar ? 'الرصيد الافتتاحي' : 'Opening balance'}</span><span class="value">${money(report.openingBalance)}</span></div>
      <div><span class="label">${ar ? 'إجمالي الفترة' : 'Period total'}</span><span class="value">${money(report.total)}</span></div>
      <div><span class="label">${ar ? 'الرصيد الختامي' : 'Closing balance'}</span><span class="value">${money(report.closingBalance)}</span></div>
    </section>
    <h3 class="section-title">${ar ? 'حسب التصنيف' : 'By category'}</h3>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'التصنيف' : 'Category'}</th>
          <th class="num">${ar ? 'العدد' : 'Count'}</th>
          <th class="num">${ar ? 'المبلغ' : 'Amount'}</th>
        </tr>
      </thead>
      <tbody>
${catRows || `        <tr><td colspan="3" class="muted center">${empty}</td></tr>`}
      </tbody>
    </table>
    <h3 class="section-title">${ar ? 'حسب الشهر' : 'By month'}</h3>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'الشهر' : 'Month'}</th>
          <th class="num">${ar ? 'المبلغ' : 'Amount'}</th>
        </tr>
      </thead>
      <tbody>
${monthRows || `        <tr><td colspan="2" class="muted center">${empty}</td></tr>`}
      </tbody>
    </table>
    <h3 class="section-title">${ar ? 'حسب الخزنة' : 'By cash box'}</h3>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'الخزنة' : 'Cash box'}</th>
          <th class="num">${ar ? 'المبلغ' : 'Amount'}</th>
        </tr>
      </thead>
      <tbody>
${boxRows || `        <tr><td colspan="2" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td>${ar ? 'الإجمالي' : 'Totals'}</td><td class="num">${money(report.total)}</td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? 'تقرير المصروفات' : 'Expense report',
    company: settings,
    showCompanyDetails: false,
    subtitle: rangeLabel(report),
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

export function shortagesHtml(
  report: ShortagesReport,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = report.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(row.sku)}</td>
        <td>${escapeHtml(row.name)}</td>
        <td class="num">${escapeHtml(row.required)}</td>
        <td class="num">${escapeHtml(row.onHand)}</td>
        <td class="num">${escapeHtml(row.shortage)}</td>
        <td class="num">${money(row.unitCost)}</td>
        <td class="num">${money(row.purchaseValue)}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا توجد نواقص' : 'Nothing is short';

  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'أصناف ناقصة' : 'Short products'}</span><span class="value">${escapeHtml(report.totals.products)}</span></div>
      <div><span class="label">${ar ? 'إجمالي النواقص' : 'Total shortage'}</span><span class="value">${escapeHtml(report.totals.shortage)}</span></div>
      <div><span class="label">${ar ? 'قيمة الشراء' : 'Purchase value'}</span><span class="value">${money(report.totals.purchaseValue)}</span></div>
    </section>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'الكود' : 'SKU'}</th>
          <th>${ar ? 'الصنف' : 'Product'}</th>
          <th class="num">${ar ? 'المطلوب' : 'Required'}</th>
          <th class="num">${ar ? 'المتوفر' : 'On hand'}</th>
          <th class="num">${ar ? 'الناقص' : 'Shortage'}</th>
          <th class="num">${ar ? 'تكلفة الوحدة' : 'Unit cost'}</th>
          <th class="num">${ar ? 'قيمة الشراء' : 'Purchase value'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="7" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td colspan="2">${ar ? 'الإجمالي' : 'Totals'}</td><td class="num">${escapeHtml(report.totals.required)}</td><td class="num">${escapeHtml(report.totals.onHand)}</td><td class="num">${escapeHtml(report.totals.shortage)}</td><td></td><td class="num">${money(report.totals.purchaseValue)}</td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? 'نواقص أوامر البيع' : 'Sales shortages',
    company: settings,
    showCompanyDetails: false,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

export function salespersonCustomerDebtHtml(
  report: SalespersonCustomerDebt,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = report.rows
    .map(
      (row, index) => `      <tr>
        <td class="num">${index + 1}</td>
        <td>${escapeHtml(row.customer)}</td>
        <td class="num">${money(row.previous)}</td>
        <td class="num">${money(row.debit)}</td>
        <td class="num">${money(row.credit)}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا توجد مديونية في هذه الفترة' : 'No debt in this period';

  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'المندوب' : 'Salesperson'}</span><span class="value">${escapeHtml(report.salesperson.name)}</span></div>
      <div><span class="label">${ar ? 'من' : 'From'}</span><span class="value">${escapeHtml(formatDate(report.from))}</span></div>
      <div><span class="label">${ar ? 'إلى' : 'To'}</span><span class="value">${escapeHtml(formatDate(report.to))}</span></div>
      <div><span class="label">${ar ? 'العرض' : 'Show'}</span><span class="value">${escapeHtml(
        report.filter === 'debtors'
          ? ar ? 'العملاء اللي عليهم فلوس' : 'Customers who owe money'
          : report.filter === 'creditors'
            ? ar ? 'العملاء اللي لهم فلوس' : 'Customers with credit'
            : ar ? 'كل العملاء' : 'All customers',
      )}</span></div>
    </section>
    <table class="data">
      <thead>
        <tr>
          <th class="num">#</th>
          <th>${ar ? 'اسم العميل' : 'Customer'}</th>
          <th class="num">${ar ? 'حساب سابق' : 'Previous'}</th>
          <th class="num">${ar ? 'مدين' : 'Debit'}</th>
          <th class="num">${ar ? 'دائن' : 'Credit'}</th>
          <th class="num">${ar ? 'الرصيد' : 'Balance'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="6" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td></td><td>${ar ? 'الإجمالي' : 'Totals'}</td><td class="num">${money(report.totals.previous)}</td><td class="num">${money(report.totals.debit)}</td><td class="num">${money(report.totals.credit)}</td><td class="num">${money(report.totals.balance)}</td></tr>
      </tbody>
    </table>`;

  const compactCss = COMPACT_TABLE_CSS;

  return renderPage({
    title: ar ? 'مديونية عملاء المندوب' : 'Salesperson customer debt',
    company: settings,
    showCompanyDetails: false,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
    extraCss: compactCss,
  });
}

export function investmentEquationHtml(
  data: {
    inventory: { total: number; rows: { name: string; sku: string | null; quantity: number; value: number }[] };
    cash: { total: number; rows: { name: string; balance: number }[] };
    customers: { total: number; rows: { name: string; balance: number }[] };
    suppliers: { total: number; rows: { name: string; balance: number }[] };
    net: number;
  },
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const section = (
    title: string,
    total: number,
    rows: { name: string; value: string }[],
  ) => `    <h3 class="section-title">${escapeHtml(title)} — ${money(total)}</h3>
    <table class="data">
      <thead><tr><th>${ar ? 'البيان' : 'Item'}</th><th class="num">${ar ? 'القيمة' : 'Value'}</th></tr></thead>
      <tbody>
${rows.map((row) => `        <tr><td>${escapeHtml(row.name)}</td><td class="num">${escapeHtml(row.value)}</td></tr>`).join('\n')}
      </tbody>
    </table>`;
  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'المخزون' : 'Inventory'}</span><span class="value">${money(data.inventory.total)}</span></div>
      <div><span class="label">${ar ? 'الخزائن' : 'Cash boxes'}</span><span class="value">${money(data.cash.total)}</span></div>
      <div><span class="label">${ar ? 'مديونية العملاء' : 'Customer debt'}</span><span class="value">${money(data.customers.total)}</span></div>
      <div><span class="label">${ar ? 'أرصدة الموردين' : 'Supplier balances'}</span><span class="value">${money(data.suppliers.total)}</span></div>
    </section>
    <h2>${ar ? 'صافي معادلة الاستثمار' : 'Investment equation net'}: ${money(data.net)}</h2>
${section(ar ? 'تفاصيل المخزون' : 'Inventory details', data.inventory.total, data.inventory.rows.map((row) => ({ name: `${row.sku ?? ''} ${row.name}`, value: `${row.quantity} · ${money(row.value)}` })))}
${section(ar ? 'تفاصيل الخزائن' : 'Cash box details', data.cash.total, data.cash.rows.map((row) => ({ name: row.name, value: money(row.balance) })))}
${section(ar ? 'تفاصيل العملاء' : 'Customer details', data.customers.total, data.customers.rows.map((row) => ({ name: row.name, value: money(row.balance) })))}
${section(ar ? 'تفاصيل الموردين' : 'Supplier details', data.suppliers.total, data.suppliers.rows.map((row) => ({ name: row.name, value: money(row.balance) })))}`;
  return renderPage({
    title: ar ? 'معادلة الاستثمار' : 'Investment equation',
    company: settings,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang: ar ? 'ar' : 'en',
  });
}

export function cashBoxStatementHtml(
  statement: BoxStatement,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = statement.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(formatDate(row.date))}</td>
        <td>${escapeHtml(row.type)}</td>
        <td>${escapeHtml(row.number)}</td>
        <td>${escapeHtml(row.description)}</td>
        <td class="num">${row.direction === 'IN' ? money(row.amount) : ''}</td>
        <td class="num">${row.direction === 'OUT' ? money(row.amount) : ''}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا توجد حركات' : 'No movements';
  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'الخزنة' : 'Cash box'}</span><span class="value">${escapeHtml(statement.box.name)}</span></div>
      <div><span class="label">${ar ? 'من' : 'From'}</span><span class="value">${statement.from ? escapeHtml(formatDate(statement.from)) : '—'}</span></div>
      <div><span class="label">${ar ? 'إلى' : 'To'}</span><span class="value">${statement.to ? escapeHtml(formatDate(statement.to)) : '—'}</span></div>
      <div><span class="label">${ar ? 'الرصيد الافتتاحي' : 'Opening'}</span><span class="value">${money(statement.openingBalance)}</span></div>
    </section>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'التاريخ' : 'Date'}</th>
          <th>${ar ? 'النوع' : 'Type'}</th>
          <th>${ar ? 'الرقم' : 'Number'}</th>
          <th>${ar ? 'البيان' : 'Description'}</th>
          <th class="num">${ar ? 'وارد' : 'In'}</th>
          <th class="num">${ar ? 'صادر' : 'Out'}</th>
          <th class="num">${ar ? 'الرصيد' : 'Balance'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="7" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td colspan="4">${ar ? 'الإجمالي' : 'Totals'}</td><td class="num">${money(statement.inTotal)}</td><td class="num">${money(statement.outTotal)}</td><td class="num">${money(statement.closingBalance)}</td></tr>
      </tbody>
    </table>`;
  return renderPage({
    title: ar ? 'كشف حساب الخزنة' : 'Cash box statement',
    company: settings,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang: ar ? 'ar' : 'en',
  });
}

export function priceListHtml(
  payload: {
    rows: {
      sku: string;
      name: string;
      unit: string;
      category: string | null;
      salePrice: number;
      boxPrice: number | null;
      cartonPrice: number | null;
      boxesPerCarton: number;
      quantity: number;
    }[];
    availableOnly: boolean;
  },
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = payload.rows
    .map(
      (row, index) => `      <tr>
        <td class="num">${index + 1}</td>
        <td>${escapeHtml(row.sku)}</td>
        <td>${escapeHtml(row.name)}</td>
        <td>${escapeHtml(row.category ?? '—')}</td>
        <td class="num">${money(row.salePrice)}</td>
        <td class="num">${row.boxPrice == null ? '—' : money(row.boxPrice)}</td>
        <td class="num">${row.cartonPrice == null ? '—' : money(row.cartonPrice)}</td>
        <td class="num">${escapeHtml(row.quantity)}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا توجد أصناف' : 'No products';
  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'الأصناف' : 'Products'}</span><span class="value">${payload.rows.length}</span></div>
      <div><span class="label">${ar ? 'العرض' : 'Show'}</span><span class="value">${payload.availableOnly ? (ar ? 'المتوفر فقط' : 'Available only') : (ar ? 'كل الأصناف' : 'All products')}</span></div>
    </section>
    <table class="data">
      <thead>
        <tr>
          <th class="num">#</th>
          <th>${ar ? 'الكود' : 'SKU'}</th>
          <th>${ar ? 'الصنف' : 'Product'}</th>
          <th>${ar ? 'التصنيف' : 'Category'}</th>
          <th class="num">${ar ? 'سعر البيع' : 'Sale price'}</th>
          <th class="num">${ar ? 'سعر العلبة' : 'Box price'}</th>
          <th class="num">${ar ? 'سعر الكرتونة' : 'Carton price'}</th>
          <th class="num">${ar ? 'المتاح' : 'Available'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="8" class="muted center">${empty}</td></tr>`}
      </tbody>
    </table>`;
  return renderPage({
    title: ar ? 'قائمة الأسعار' : 'Price list',
    company: settings,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang: ar ? 'ar' : 'en',
  });
}

export function customerBalancesHtml(
  rows: {
    name: string;
    phone: string | null;
    salesperson: string | null;
    balance: number;
    invoices: number;
  }[],
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const bodyRows = rows
    .map(
      (row, index) => `      <tr>
        <td class="num">${index + 1}</td>
        <td>${escapeHtml(row.name)}</td>
        <td>${escapeHtml(row.phone ?? '—')}</td>
        <td>${escapeHtml(row.salesperson ?? '—')}</td>
        <td class="num">${escapeHtml(row.invoices)}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`,
    )
    .join('\n');
  const total = rows.reduce((sum, row) => sum + Number(row.balance), 0);
  const empty = ar ? 'لا توجد أرصدة' : 'No balances';
  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'عدد العملاء' : 'Customers'}</span><span class="value">${rows.length}</span></div>
      <div><span class="label">${ar ? 'إجمالي الأرصدة' : 'Total balance'}</span><span class="value">${money(total)}</span></div>
    </section>
    <table class="data">
      <thead>
        <tr>
          <th class="num">#</th>
          <th>${ar ? 'العميل' : 'Customer'}</th>
          <th>${ar ? 'الهاتف' : 'Phone'}</th>
          <th>${ar ? 'المندوب' : 'Salesperson'}</th>
          <th class="num">${ar ? 'الفواتير' : 'Invoices'}</th>
          <th class="num">${ar ? 'الرصيد' : 'Balance'}</th>
        </tr>
      </thead>
      <tbody>
${bodyRows || `        <tr><td colspan="6" class="muted center">${empty}</td></tr>`}
      </tbody>
    </table>`;
  return renderPage({
    title: ar ? 'أرصدة العملاء' : 'Customer balances',
    company: settings,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang: ar ? 'ar' : 'en',
  });
}

/** Collection receipts grouped by the cash box that received the money. */
export function collectionsByBoxHtml(
  report: CollectionsByBoxReport,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const sections = report.boxes
    .map((box) => {
      const rows = box.vouchers
        .map(
          (voucher) => `      <tr>
        <td>${escapeHtml(formatDate(voucher.collectedAt))}</td>
        <td>${escapeHtml(voucher.number)}</td>
        <td>${escapeHtml(voucher.salesperson ?? '—')}</td>
        <td>${escapeHtml(voucher.lines.map((line) => line.customer ?? '—').join('، '))}</td>
        <td class="num">${money(voucher.total)}</td>
      </tr>`,
        )
        .join('\n');
      return `    <h3>${escapeHtml(box.cashBoxCode)} — ${escapeHtml(box.cashBoxName)} (${money(box.total)})</h3>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'التاريخ' : 'Date'}</th>
          <th>${ar ? 'رقم الإيصال' : 'Receipt'}</th>
          <th>${ar ? 'المندوب' : 'Salesperson'}</th>
          <th>${ar ? 'العملاء' : 'Customers'}</th>
          <th class="num">${ar ? 'المبلغ' : 'Amount'}</th>
        </tr>
      </thead>
      <tbody>
${rows}
        <tr class="total"><td colspan="4">${ar ? 'إجمالي الخزنة' : 'Box total'}</td><td class="num">${money(box.total)}</td></tr>
      </tbody>
    </table>`;
    })
    .join('\n');
  const empty = ar ? 'لا توجد تحصيلات في هذه الفترة' : 'No collections in this period';

  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'عدد الإيصالات' : 'Receipts'}</span><span class="value">${escapeHtml(report.count)}</span></div>
      <div><span class="label">${ar ? 'الإجمالي' : 'Total'}</span><span class="value">${money(report.total)}</span></div>
      <div><span class="label">${ar ? 'من' : 'From'}</span><span class="value">${escapeHtml(formatDate(report.from))}</span></div>
      <div><span class="label">${ar ? 'إلى' : 'To'}</span><span class="value">${escapeHtml(formatDate(report.to))}</span></div>
    </section>
${sections || `    <p class="muted center">${empty}</p>`}`;

  return renderPage({
    title: ar ? 'إيصالات التحصيل حسب الخزنة' : 'Collections by cash box',
    company: settings,
    showCompanyDetails: false,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

/** A statement of every expense under one category over a period. */
export function expenseCategoryStatementHtml(
  report: ExpenseReport,
  categoryName: string,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  let running = round2(report.openingBalance);
  const rows = report.expenses
    .map((expense) => {
      const amount = round2(Number(expense.amount));
      running = round2(running + amount);
      const description = [expense.payee, expense.note ?? expense.reference]
        .filter((value): value is string => Boolean(value))
        .join(' — ') || expense.number;
      return `      <tr>
        <td>${escapeHtml(formatDate(expense.spentAt))}</td>
        <td>${escapeHtml(expense.number)}</td>
        <td>${escapeHtml(description)}</td>
        <td class="num">${money(amount)}</td>
        <td class="num">${money(0)}</td>
        <td class="num">${money(running)}</td>
      </tr>`;
    })
    .join('\n');
  const empty = ar ? 'لا توجد مصروفات في هذه الفترة' : 'No expenses in this period';

  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'البند' : 'Category'}</span><span class="value">${escapeHtml(categoryName)}</span></div>
      <div><span class="label">${ar ? 'الفترة' : 'Period'}</span><span class="value">${escapeHtml(formatDate(report.from))} → ${escapeHtml(formatDate(report.to))}</span></div>
    </section>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'التاريخ' : 'Date'}</th>
          <th>${ar ? 'الرقم' : 'Number'}</th>
          <th>${ar ? 'البيان' : 'Description'}</th>
          <th class="num">${ar ? 'مدين' : 'Debit'}</th>
          <th class="num">${ar ? 'دائن' : 'Credit'}</th>
          <th class="num">${ar ? 'الرصيد' : 'Balance'}</th>
        </tr>
      </thead>
      <tbody>
        <tr class="muted">
          <td colspan="5">${ar ? 'رصيد افتتاحي' : 'Opening balance'}</td>
          <td class="num">${money(report.openingBalance)}</td>
        </tr>
${rows || `        <tr><td colspan="6" class="muted center">${empty}</td></tr>`}
        <tr class="total">
          <td colspan="3">${ar ? 'الإجمالي' : 'Total'}</td>
          <td class="num">${money(report.total)}</td>
          <td class="num">${money(0)}</td>
          <td class="num">${money(report.closingBalance)}</td>
        </tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? `كشف بند: ${categoryName}` : `Expense statement: ${categoryName}`,
    company: settings,
    showCompanyDetails: false,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

/** The order-fulfilment board: available vs. needed per open sales order. */
export function orderFulfilmentHtml(
  report: OrderFulfilmentReport,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const sections = report.rows
    .map((order) => {
      const rows = order.lines
        .map(
          (line) => `      <tr>
        <td>${escapeHtml(line.sku)}</td>
        <td>${escapeHtml(line.name)}</td>
        <td class="num">${escapeHtml(line.required)}</td>
        <td class="num">${escapeHtml(line.available)}</td>
        <td class="num">${escapeHtml(line.shortage)}</td>
      </tr>`,
        )
        .join('\n');
      const status = order.fullyAvailable
        ? ar
          ? 'جاهز للتسليم'
          : 'Ready to deliver'
        : ar
          ? 'يحتاج شراء'
          : 'Needs purchasing';
      return `    <h3>${escapeHtml(order.orderNumber)} — ${escapeHtml(order.customer ?? (ar ? 'عميل نقدي' : 'Walk-in'))} (${status})</h3>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'الكود' : 'SKU'}</th>
          <th>${ar ? 'الصنف' : 'Product'}</th>
          <th class="num">${ar ? 'المطلوب' : 'Required'}</th>
          <th class="num">${ar ? 'المتاح' : 'Available'}</th>
          <th class="num">${ar ? 'المطلوب شراؤه' : 'To buy'}</th>
        </tr>
      </thead>
      <tbody>
${rows}
      </tbody>
    </table>`;
    })
    .join('\n');
  const empty = ar ? 'لا توجد أوامر بيع مفتوحة' : 'No open sales orders';

  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'أوامر مفتوحة' : 'Open orders'}</span><span class="value">${escapeHtml(report.totals.orders)}</span></div>
      <div><span class="label">${ar ? 'المطلوب' : 'Required'}</span><span class="value">${escapeHtml(report.totals.required)}</span></div>
      <div><span class="label">${ar ? 'المتاح' : 'Available'}</span><span class="value">${escapeHtml(report.totals.available)}</span></div>
      <div><span class="label">${ar ? 'المطلوب شراؤه' : 'To buy'}</span><span class="value">${escapeHtml(report.totals.shortage)}</span></div>
    </section>
${sections || `    <p class="muted center">${empty}</p>`}`;

  return renderPage({
    title: ar ? 'المتاح والمطلوب لكل أمر بيع' : 'Available vs. needed per order',
    company: settings,
    showCompanyDetails: false,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}

/** A settlements statement (كشف التسويات) for a period. */
export interface SettlementStatementRow {
  number: string;
  settledAt: Date;
  target: string;
  accountName: string;
  direction: string;
  amount: number;
  reference: string | null;
  note: string | null;
  userName: string | null;
}

export interface SettlementStatementReport {
  rows: SettlementStatementRow[];
  count: number;
  increaseTotal: number;
  decreaseTotal: number;
  netTotal: number;
  from: Date;
  to: Date;
}

export function settlementsStatementHtml(
  report: SettlementStatementReport,
  settings: AppSettings,
  lang = 'en',
): string {
  const ar = isArabic(lang);
  const rows = report.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(formatDate(row.settledAt))}</td>
        <td>${escapeHtml(row.number)}</td>
        <td>${escapeHtml(row.target)}</td>
        <td>${escapeHtml(row.accountName || '—')}</td>
        <td>${escapeHtml(
          row.direction === 'INCREASE'
            ? ar
              ? 'زيادة'
              : 'Increase'
            : ar
              ? 'خصم'
              : 'Decrease',
        )}</td>
        <td class="num">${money(row.amount)}</td>
        <td>${escapeHtml(row.note ?? row.reference ?? '—')}</td>
      </tr>`,
    )
    .join('\n');
  const empty = ar ? 'لا توجد تسويات في هذه الفترة' : 'No settlements in this period';

  const body = `    <section class="meta">
      <div><span class="label">${ar ? 'عدد التسويات' : 'Entries'}</span><span class="value">${escapeHtml(report.count)}</span></div>
      <div><span class="label">${ar ? 'إجمالي الزيادة' : 'Increases'}</span><span class="value">${money(report.increaseTotal)}</span></div>
      <div><span class="label">${ar ? 'إجمالي الخصم' : 'Decreases'}</span><span class="value">${money(report.decreaseTotal)}</span></div>
      <div><span class="label">${ar ? 'الصافي' : 'Net'}</span><span class="value">${money(report.netTotal)}</span></div>
      <div><span class="label">${ar ? 'الفترة' : 'Period'}</span><span class="value">${escapeHtml(formatDate(report.from))} → ${escapeHtml(formatDate(report.to))}</span></div>
    </section>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'التاريخ' : 'Date'}</th>
          <th>${ar ? 'الرقم' : 'Number'}</th>
          <th>${ar ? 'النوع' : 'Type'}</th>
          <th>${ar ? 'الحساب' : 'Account'}</th>
          <th>${ar ? 'الأثر' : 'Effect'}</th>
          <th class="num">${ar ? 'المبلغ' : 'Amount'}</th>
          <th>${ar ? 'ملاحظات' : 'Notes'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="7" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td colspan="5">${ar ? 'الصافي' : 'Net'}</td><td class="num">${money(report.netTotal)}</td><td></td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? 'كشف التسويات' : 'Settlements statement',
    company: settings,
    showCompanyDetails: false,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}
