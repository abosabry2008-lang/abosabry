import { Prisma } from '@prisma/client';
import { lineTotals, num } from '../../lib/money';
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

/** Formats a Date / date string as YYYY-MM-DD. */
export function formatDate(value: unknown): string {
  if (value === null || value === undefined || value === '') return '';
  const date = value instanceof Date ? value : new Date(String(value));
  if (Number.isNaN(date.getTime())) return '';
  return date.toISOString().slice(0, 10);
}

function timestamp(): string {
  return `${new Date().toISOString().replace('T', ' ').slice(0, 19)} UTC`;
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
  table.data th, table.data td { border: 1px solid #e2e8f0; padding: 7px 10px; vertical-align: top; }
  table.data thead th {
    background: #0f172a;
    color: #ffffff;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    text-align: left;
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

export interface PageOptions {
  title: string;
  company: AppSettings;
  subtitle?: string;
  body: string;
  /** Text direction of the page (`rtl` for Arabic). Defaults to `ltr`. */
  dir?: 'ltr' | 'rtl';
  /** Document language attribute. Defaults to `en`. */
  lang?: string;
}

/** Wraps a document body in a self-contained, printable HTML page. */
export function renderPage({
  title,
  company,
  subtitle,
  body,
  dir = 'ltr',
  lang = 'en',
}: PageOptions): string {
  const companyName = escapeHtml(company.companyName || 'ERP');
  const contact: string[] = [];
  if (company.companyAddress) contact.push(`<div class="muted">${escapeHtml(company.companyAddress)}</div>`);
  if (company.companyPhone) contact.push(`<div class="muted">${escapeHtml(company.companyPhone)}</div>`);
  if (company.companyEmail) contact.push(`<div class="muted">${escapeHtml(company.companyEmail)}</div>`);

  return `<!doctype html>
<html lang="${escapeHtml(lang)}" dir="${dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>${STYLES}</style>
</head>
<body>
<div class="page">
  <header class="doc-header">
    <div class="company">
      <h1>${companyName}</h1>
      ${contact.join('\n      ')}
    </div>
    <div class="doc-title">
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

export function invoiceHtml(invoice: InvoiceWithRelations, settings: AppSettings): string {
  const currency = invoice.currency
    ? `${invoice.currency.code} (${invoice.currency.symbol})`
    : settings.baseCurrencyCode;

  const lineRows = invoice.lines
    .map((line, index) => {
      const totals = lineTotals({
        quantity: line.quantity,
        unitPrice: Number(line.unitPrice),
        discount: Number(line.discount),
        taxRate: Number(line.taxRate),
      });
      return `      <tr>
        <td class="num">${index + 1}</td>
        <td>${escapeHtml(line.product?.sku ?? '—')}</td>
        <td>${escapeHtml(line.description)}</td>
        <td class="num">${escapeHtml(line.quantity)}</td>
        <td class="num">${money(line.unitPrice)}</td>
        <td class="num">${money(line.discount)}</td>
        <td class="num">${money(totals.tax)}</td>
        <td class="num">${money(line.total)}</td>
      </tr>`;
    })
    .join('\n');

  const customer = invoice.customer;
  const customerLines = customer
    ? [
        `<div>${escapeHtml(customer.name)}</div>`,
        customer.address ? `<div class="muted">${escapeHtml(customer.address)}</div>` : '',
        customer.email ? `<div class="muted">${escapeHtml(customer.email)}</div>` : '',
        customer.phone ? `<div class="muted">${escapeHtml(customer.phone)}</div>` : '',
      ].join('\n    ')
    : '<div class="muted">Walk-in customer</div>';

  const body = `    <section class="meta">
      <div><span class="label">Invoice</span><span class="value">${escapeHtml(invoice.number)}</span></div>
      <div><span class="label">Status</span><span class="value">${escapeHtml(invoice.status)}</span></div>
      <div><span class="label">Issue date</span><span class="value">${escapeHtml(formatDate(invoice.issueDate))}</span></div>
      <div><span class="label">Due date</span><span class="value">${escapeHtml(invoice.dueDate ? formatDate(invoice.dueDate) : '—')}</span></div>
      <div><span class="label">Currency</span><span class="value">${escapeHtml(currency)}</span></div>
      <div><span class="label">Reference</span><span class="value">${escapeHtml(invoice.salesOrder?.number ?? '—')}</span></div>
    </section>
    <section class="panel">
      <h3>Bill to</h3>
      ${customerLines}
    </section>
    <table class="data">
      <thead>
        <tr>
          <th class="num">#</th>
          <th>SKU</th>
          <th>Description</th>
          <th class="num">Qty</th>
          <th class="num">Unit price</th>
          <th class="num">Discount</th>
          <th class="num">Tax</th>
          <th class="num">Line total</th>
        </tr>
      </thead>
      <tbody>
${lineRows || '        <tr><td colspan="8" class="muted center">No lines</td></tr>'}
      </tbody>
    </table>
    <div class="totals-wrap">
      <table class="totals">
        <tbody>
          <tr><th>Subtotal</th><td class="num">${money(invoice.subtotal)}</td></tr>
          <tr><th>Discount</th><td class="num">${money(invoice.discountTotal)}</td></tr>
          <tr><th>Tax</th><td class="num">${money(invoice.taxTotal)}</td></tr>
          <tr class="grand"><th>Total</th><td class="num">${money(invoice.total)}</td></tr>
          <tr><th>Paid</th><td class="num">${money(invoice.amountPaid)}</td></tr>
          <tr class="grand"><th>Balance due</th><td class="num">${money(invoice.balance)}</td></tr>
        </tbody>
      </table>
    </div>${
      invoice.notes
        ? `
    <section class="panel">
      <h3>Notes</h3>
      <div>${escapeHtml(invoice.notes)}</div>
    </section>`
        : ''
    }
`;

  return renderPage({ title: `Invoice ${invoice.number}`, company: settings, body });
}

// ---------------------------------------------------------------------------
// Account statements
// ---------------------------------------------------------------------------

const ROW_TYPE_LABEL: Record<StatementRowType, string> = {
  INVOICE: 'Invoice',
  PAYMENT: 'Payment',
  PURCHASE_ORDER: 'Purchase order',
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

function statementBody(view: StatementView, party: PartyInfo): string {
  const rows = view.rows
    .map(
      (row) => `      <tr>
        <td>${escapeHtml(formatDate(row.date))}</td>
        <td>${escapeHtml(ROW_TYPE_LABEL[row.type])}</td>
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
      <div><span class="label">Account</span><span class="value">${escapeHtml(party.name)}</span></div>
      <div><span class="label">From</span><span class="value">${escapeHtml(view.from ?? '—')}</span></div>
      <div><span class="label">To</span><span class="value">${escapeHtml(view.to ?? '—')}</span></div>
      <div><span class="label">Opening balance</span><span class="value">${money(view.openingBalance)}</span></div>
    </section>
    <section class="panel">
      <h3>${escapeHtml(party.heading)}</h3>
      <div>${escapeHtml(party.name)}</div>
${contact}
    </section>
    <table class="data">
      <thead>
        <tr>
          <th>Date</th>
          <th>Type</th>
          <th>Number</th>
          <th>Description</th>
          <th class="num">Debit</th>
          <th class="num">Credit</th>
          <th class="num">Balance</th>
        </tr>
      </thead>
      <tbody>
        <tr class="muted"><td colspan="6">Opening balance</td><td class="num">${money(view.openingBalance)}</td></tr>
${rows || '        <tr><td colspan="7" class="muted center">No transactions in this period</td></tr>'}
        <tr class="total"><td colspan="4">Totals</td><td class="num">${money(view.totals.debit)}</td><td class="num">${money(view.totals.credit)}</td><td class="num">${money(view.totals.closingBalance)}</td></tr>
      </tbody>
    </table>`;
}

export function customerStatementHtml(statement: CustomerStatement, settings: AppSettings): string {
  const body = statementBody(statement, {
    heading: 'Customer',
    name: statement.customer.name,
    lines: [statement.customer.address, statement.customer.email, statement.customer.phone],
  });
  return renderPage({
    title: 'Customer statement',
    company: settings,
    subtitle: statement.customer.name,
    body,
  });
}

export function supplierStatementHtml(statement: SupplierStatement, settings: AppSettings): string {
  const body = statementBody(statement, {
    heading: 'Supplier',
    name: statement.supplier.name,
    lines: [statement.supplier.address, statement.supplier.email, statement.supplier.phone],
  });
  return renderPage({
    title: 'Supplier statement',
    company: settings,
    subtitle: statement.supplier.name,
    body,
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

  return renderPage({ title: 'Inventory valuation', company: settings, body });
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
    subtitle: rangeLabel(report),
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
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
${rows || `        <tr><td colspan="10" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td colspan="5">${ar ? 'الإجمالي' : 'Totals'}</td><td class="num">${escapeHtml(report.totals.inQty)}</td><td class="num">${escapeHtml(report.totals.outQty)}</td><td class="num">${escapeHtml(report.totals.closingQty)}</td><td></td><td class="num">${money(report.totals.closingValue)}</td></tr>
      </tbody>
    </table>`;

  return renderPage({
    title: ar ? 'حركة صنف' : 'Item movement',
    company: settings,
    subtitle: `${report.product.name} (${report.product.sku})`,
    body,
    dir: ar ? 'rtl' : 'ltr',
    lang,
  });
}
