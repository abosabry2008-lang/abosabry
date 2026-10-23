"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.escapeHtml = escapeHtml;
exports.formatMoney = formatMoney;
exports.formatDate = formatDate;
exports.renderPage = renderPage;
exports.invoiceHtml = invoiceHtml;
exports.customerStatementHtml = customerStatementHtml;
exports.supplierStatementHtml = supplierStatementHtml;
exports.salesReportHtml = salesReportHtml;
exports.inventoryValuationHtml = inventoryValuationHtml;
exports.topProductsHtml = topProductsHtml;
exports.receivablesBySalespersonHtml = receivablesBySalespersonHtml;
exports.supplierPayablesHtml = supplierPayablesHtml;
exports.stockBalanceHtml = stockBalanceHtml;
exports.itemMovementHtml = itemMovementHtml;
exports.consolidatedSalesNoteHtml = consolidatedSalesNoteHtml;
exports.profitBySalespersonHtml = profitBySalespersonHtml;
exports.collectionsBySalespersonHtml = collectionsBySalespersonHtml;
exports.salespersonStatementHtml = salespersonStatementHtml;
exports.expenseReportHtml = expenseReportHtml;
exports.shortagesHtml = shortagesHtml;
exports.salespersonCustomerDebtHtml = salespersonCustomerDebtHtml;
exports.collectionsByBoxHtml = collectionsByBoxHtml;
exports.expenseCategoryStatementHtml = expenseCategoryStatementHtml;
exports.orderFulfilmentHtml = orderFulfilmentHtml;
exports.settlementsStatementHtml = settlementsStatementHtml;
const money_1 = require("../../lib/money");
// ---------------------------------------------------------------------------
// Small formatting / safety helpers
// ---------------------------------------------------------------------------
/** Escapes a value for safe interpolation into HTML text or attributes. */
function escapeHtml(value) {
    if (value === null || value === undefined)
        return '';
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}
/** Formats money with 2 decimals and thousands separators (no dependencies). */
function formatMoney(value) {
    const n = (0, money_1.num)(value);
    const negative = n < 0;
    const [whole, decimals] = Math.abs(n).toFixed(2).split('.');
    const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    return `${negative ? '-' : ''}${grouped}.${decimals}`;
}
function money(value) {
    return formatMoney(value);
}
/** Formats a Date / date string as YYYY-MM-DD. */
function formatDate(value) {
    if (value === null || value === undefined || value === '')
        return '';
    const date = value instanceof Date ? value : new Date(String(value));
    if (Number.isNaN(date.getTime()))
        return '';
    return date.toISOString().slice(0, 10);
}
function timestamp() {
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
/** Wraps a document body in a self-contained, printable HTML page. */
function renderPage({ title, company, subtitle, body, dir = 'ltr', lang = 'en', showCompanyDetails = true, }) {
    const companyName = escapeHtml(company.companyName || 'ERP');
    const contact = [];
    if (showCompanyDetails) {
        if (company.companyAddress)
            contact.push(`<div class="muted">${escapeHtml(company.companyAddress)}</div>`);
        if (company.companyPhone)
            contact.push(`<div class="muted">${escapeHtml(company.companyPhone)}</div>`);
        if (company.companyEmail)
            contact.push(`<div class="muted">${escapeHtml(company.companyEmail)}</div>`);
        // Legal identifiers shown on printed documents (invoice, statement, ...).
        if (company.commercialRegisterNo) {
            contact.push(`<div class="muted">السجل التجاري / Commercial register: ${escapeHtml(company.commercialRegisterNo)}</div>`);
        }
        if (company.taxCardNo) {
            contact.push(`<div class="muted">البطاقة الضريبية / Tax card: ${escapeHtml(company.taxCardNo)}</div>`);
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
<style>${STYLES}</style>
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
function invoiceHtml(invoice, settings, options = {}) {
    const ar = (options.lang ?? 'en') === 'ar';
    const t = (en, arabic) => (ar ? arabic : en);
    const currency = invoice.currency
        ? `${invoice.currency.code} (${invoice.currency.symbol})`
        : settings.baseCurrencyCode;
    // What the customer already owed before this invoice (open balance on their
    // other documents plus any opening balance).
    const previousBalance = (0, money_1.round2)(Number(options.previousBalance ?? 0));
    const lineRows = invoice.lines
        .map((line, index) => {
        const totals = (0, money_1.lineTotals)({
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
        : `<div class="muted">${escapeHtml(t('Walk-in customer', 'عميل نقدي'))}</div>`;
    const body = `    <section class="meta">
      <div><span class="label">${escapeHtml(t('Invoice', 'فاتورة'))}</span><span class="value">${escapeHtml(invoice.number)}</span></div>
      <div><span class="label">${escapeHtml(t('Status', 'الحالة'))}</span><span class="value">${escapeHtml(ar ? invoiceStatusAr(invoice.status) : invoice.status)}</span></div>
      <div><span class="label">${escapeHtml(t('Issue date', 'تاريخ الإصدار'))}</span><span class="value">${escapeHtml(formatDate(invoice.issueDate))}</span></div>
      <div><span class="label">${escapeHtml(t('Due date', 'تاريخ الاستحقاق'))}</span><span class="value">${escapeHtml(invoice.dueDate ? formatDate(invoice.dueDate) : '—')}</span></div>
      <div><span class="label">${escapeHtml(t('Currency', 'العملة'))}</span><span class="value">${escapeHtml(currency)}</span></div>
      <div><span class="label">${escapeHtml(t('Reference', 'المرجع'))}</span><span class="value">${escapeHtml(invoice.salesOrder?.number ?? '—')}</span></div>
    </section>
    <section class="panel">
      <h3>${escapeHtml(t('Bill to', 'العميل'))}</h3>
      ${customerLines}
    </section>
    <table class="data">
      <thead>
        <tr>
          <th class="num">#</th>
          <th>${escapeHtml(t('SKU', 'كود الصنف'))}</th>
          <th>${escapeHtml(t('Description', 'الوصف'))}</th>
          <th class="num">${escapeHtml(t('Qty', 'الكمية'))}</th>
          <th class="num">${escapeHtml(t('Unit price', 'سعر الوحدة'))}</th>
          <th class="num">${escapeHtml(t('Discount', 'الخصم'))}</th>
          <th class="num">${escapeHtml(t('Tax', 'الضريبة'))}</th>
          <th class="num">${escapeHtml(t('Line total', 'إجمالي السطر'))}</th>
        </tr>
      </thead>
      <tbody>
${lineRows || `        <tr><td colspan="8" class="muted center">${escapeHtml(t('No lines', 'لا توجد أصناف'))}</td></tr>`}
      </tbody>
    </table>
    <div class="totals-wrap">
      <table class="totals">
        <tbody>
          <tr><th>${escapeHtml(t('Subtotal', 'الإجمالي الفرعي'))}</th><td class="num">${money(invoice.subtotal)}</td></tr>
          <tr><th>${escapeHtml(t('Discount', 'الخصم'))}</th><td class="num">${money(invoice.discountTotal)}</td></tr>
          <tr><th>${escapeHtml(t('Tax', 'الضريبة'))}</th><td class="num">${money(invoice.taxTotal)}</td></tr>
          <tr class="grand"><th>${escapeHtml(t('Total', 'الإجمالي'))}</th><td class="num">${money(invoice.total)}</td></tr>
          <tr><th>${escapeHtml(t('Paid', 'المدفوع'))}</th><td class="num">${money(invoice.amountPaid)}</td></tr>
          <tr class="grand"><th>${escapeHtml(t('Balance due', 'المستحق'))}</th><td class="num">${money(invoice.balance)}</td></tr>${customer && previousBalance !== 0
        ? `
          <tr><th>${escapeHtml(t('Previous balance', 'الرصيد السابق'))}</th><td class="num">${money(previousBalance)}</td></tr>
          <tr class="grand"><th>${escapeHtml(t('Total due', 'إجمالي المديونية'))}</th><td class="num">${money((0, money_1.round2)(previousBalance + Number(invoice.balance)))}</td></tr>`
        : ''}
        </tbody>
      </table>
    </div>${invoice.notes
        ? `
    <section class="panel">
      <h3>${escapeHtml(t('Notes', 'ملاحظات'))}</h3>
      <div>${escapeHtml(invoice.notes)}</div>
    </section>`
        : ''}
`;
    return renderPage({
        title: `${t('Invoice', 'فاتورة')} ${invoice.number}`,
        company: settings,
        body,
        dir: ar ? 'rtl' : 'ltr',
        lang: ar ? 'ar' : 'en',
    });
}
/** Arabic label for an invoice status. */
function invoiceStatusAr(status) {
    switch (status) {
        case 'DRAFT':
            return 'مسودة';
        case 'ISSUED':
            return 'مُصدرة';
        case 'PARTIALLY_PAID':
            return 'مدفوعة جزئيًا';
        case 'PAID':
            return 'مدفوعة';
        case 'VOID':
            return 'ملغاة';
        default:
            return status;
    }
}
// ---------------------------------------------------------------------------
// Account statements
// ---------------------------------------------------------------------------
const ROW_TYPE_LABEL = {
    INVOICE: 'Invoice',
    PAYMENT: 'Payment',
    PURCHASE_ORDER: 'Purchase order',
};
const ROW_TYPE_LABEL_AR = {
    INVOICE: 'فاتورة',
    PAYMENT: 'سداد',
    PURCHASE_ORDER: 'أمر شراء',
};
function statementBody(view, party, lang = 'en') {
    const ar = lang === 'ar';
    const t = (en, arabic) => (ar ? arabic : en);
    const typeLabels = ar ? ROW_TYPE_LABEL_AR : ROW_TYPE_LABEL;
    const rows = view.rows
        .map((row) => `      <tr>
        <td>${escapeHtml(formatDate(row.date))}</td>
        <td>${escapeHtml(typeLabels[row.type])}</td>
        <td>${escapeHtml(row.number)}</td>
        <td>${escapeHtml(row.description)}</td>
        <td class="num">${row.debit ? money(row.debit) : ''}</td>
        <td class="num">${row.credit ? money(row.credit) : ''}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`)
        .join('\n');
    const contact = party.lines
        .filter((line) => Boolean(line))
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
function customerStatementHtml(statement, settings, lang = 'en') {
    const ar = lang === 'ar';
    const body = statementBody(statement, {
        heading: ar ? 'العميل' : 'Customer',
        name: statement.customer.name,
        lines: [statement.customer.address, statement.customer.email, statement.customer.phone],
    }, lang);
    return renderPage({
        title: ar ? 'كشف حساب عميل' : 'Customer statement',
        company: settings,
        subtitle: statement.customer.name,
        body,
        dir: ar ? 'rtl' : 'ltr',
        lang: ar ? 'ar' : 'en',
    });
}
function supplierStatementHtml(statement, settings, lang = 'en') {
    const ar = lang === 'ar';
    const body = statementBody(statement, {
        heading: ar ? 'المورد' : 'Supplier',
        name: statement.supplier.name,
        lines: [statement.supplier.address, statement.supplier.email, statement.supplier.phone],
    }, lang);
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
function salesReportHtml(report, settings) {
    const rows = report.series
        .map((bucket) => `      <tr>
        <td>${escapeHtml(bucket.period)}</td>
        <td class="num">${escapeHtml(bucket.orders)}</td>
        <td class="num">${money(bucket.subtotal)}</td>
        <td class="num">${money(bucket.discount)}</td>
        <td class="num">${money(bucket.tax)}</td>
        <td class="num">${money(bucket.total)}</td>
      </tr>`)
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
function inventoryValuationHtml(report, settings) {
    const rows = report.rows
        .map((row) => `      <tr>
        <td>${escapeHtml(row.sku)}</td>
        <td>${escapeHtml(row.name)}</td>
        <td>${escapeHtml(row.warehouse.name)}</td>
        <td>${escapeHtml(row.location.name ?? row.location.code)}</td>
        <td class="num">${escapeHtml(row.quantity)}</td>
        <td class="num">${money(row.unitCost)}</td>
        <td class="num">${money(row.costValue)}</td>
        <td class="num">${money(row.unitPrice)}</td>
        <td class="num">${money(row.retailValue)}</td>
      </tr>`)
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
function topProductsHtml(report, settings) {
    const rows = report.rows
        .map((row, index) => `      <tr>
        <td class="num">${index + 1}</td>
        <td>${escapeHtml(row.sku)}</td>
        <td>${escapeHtml(row.name)}</td>
        <td class="num">${escapeHtml(row.quantitySold)}</td>
        <td class="num">${escapeHtml(row.orders)}</td>
        <td class="num">${money(row.revenue)}</td>
      </tr>`)
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
const isArabic = (lang) => lang === 'ar';
const rangeLabel = (report) => report.from && report.to ? `${formatDate(report.from)} - ${formatDate(report.to)}` : undefined;
function receivablesBySalespersonHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const rows = report.rows
        .map((row) => `      <tr>
        <td>${escapeHtml(row.salesperson ?? (ar ? 'بدون مندوب' : 'Unassigned'))}</td>
        <td>${escapeHtml(row.customer ?? '—')}</td>
        <td class="num">${escapeHtml(row.invoices)}</td>
        <td class="num">${money(row.total)}</td>
        <td class="num">${money(row.paid)}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`)
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
    });
}
function supplierPayablesHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const rows = report.rows
        .map((row) => `      <tr>
        <td>${escapeHtml(row.supplier)}</td>
        <td>${escapeHtml(row.phone ?? '—')}</td>
        <td class="num">${escapeHtml(row.purchaseOrders)}</td>
        <td class="num">${money(row.purchases)}</td>
        <td class="num">${money(row.paid)}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`)
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
function stockBalanceHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const rows = report.rows
        .map((row) => `      <tr>
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
      </tr>`)
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
function itemMovementHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const rows = report.rows
        .map((row) => `      <tr>
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
      </tr>`)
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
function consolidatedSalesNoteHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const unassigned = ar ? 'بدون مندوب' : 'Unassigned';
    const sections = report.rows
        .map((rep) => {
        const rows = rep.lines
            .map((line) => `      <tr>
        <td>${escapeHtml(line.sku)}</td>
        <td>${escapeHtml(line.name)}</td>
        <td>${escapeHtml(line.unit)}</td>
        <td class="num">${escapeHtml(line.quantity)}</td>
        <td class="num">${money(line.net)}</td>
      </tr>`)
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
function profitBySalespersonHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const rows = report.rows
        .map((row) => `      <tr>
        <td>${escapeHtml(row.salesperson ?? (ar ? 'بدون مندوب' : 'Unassigned'))}</td>
        <td class="num">${escapeHtml(row.orders)}</td>
        <td class="num">${money(row.revenue)}</td>
        <td class="num">${money(row.cost)}</td>
        <td class="num">${money(row.profit)}</td>
        <td class="num">${escapeHtml(row.margin)}%</td>
      </tr>`)
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
function collectionsBySalespersonHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const rows = report.rows
        .map((row) => `      <tr>
        <td>${escapeHtml(row.salesperson ?? (ar ? 'بدون مندوب' : 'Unassigned'))}</td>
        <td class="num">${escapeHtml(row.vouchers)}</td>
        <td class="num">${money(row.amount)}</td>
      </tr>`)
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
function salespersonStatementHtml(statement, settings, lang = 'en') {
    const ar = isArabic(lang);
    const rows = statement.rows
        .map((row) => `      <tr>
        <td>${escapeHtml(formatDate(row.date))}</td>
        <td>${escapeHtml(row.type === 'SALE' ? (ar ? 'فاتورة' : 'Invoice') : ar ? 'تحصيل' : 'Collection')}</td>
        <td>${escapeHtml(row.reference)}</td>
        <td>${escapeHtml(row.customer ?? '—')}</td>
        <td class="num">${row.debit ? money(row.debit) : ''}</td>
        <td class="num">${row.credit ? money(row.credit) : ''}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`)
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
function expenseReportHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const catRows = report.categories
        .map((row) => `      <tr>
        <td>${escapeHtml(row.name)}</td>
        <td class="num">${escapeHtml(row.count)}</td>
        <td class="num">${money(row.amount)}</td>
      </tr>`)
        .join('\n');
    const monthRows = report.months
        .map((row) => `      <tr>
        <td>${escapeHtml(row.month)}</td>
        <td class="num">${money(row.amount)}</td>
      </tr>`)
        .join('\n');
    const boxRows = report.boxes
        .map((row) => `      <tr>
        <td>${escapeHtml(row.name)}</td>
        <td class="num">${money(row.amount)}</td>
      </tr>`)
        .join('\n');
    const empty = ar ? 'لا مصروفات في هذه الفترة' : 'No expenses in this period';
    const body = `    <section class="meta">
      <div><span class="label">${ar ? 'عدد المصروفات' : 'Expenses'}</span><span class="value">${escapeHtml(report.count)}</span></div>
      <div><span class="label">${ar ? 'الإجمالي' : 'Total'}</span><span class="value">${money(report.total)}</span></div>
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
function shortagesHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const rows = report.rows
        .map((row) => `      <tr>
        <td>${escapeHtml(row.sku)}</td>
        <td>${escapeHtml(row.name)}</td>
        <td class="num">${escapeHtml(row.required)}</td>
        <td class="num">${escapeHtml(row.onHand)}</td>
        <td class="num">${escapeHtml(row.shortage)}</td>
        <td class="num">${money(row.unitCost)}</td>
        <td class="num">${money(row.purchaseValue)}</td>
      </tr>`)
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
function salespersonCustomerDebtHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const rows = report.rows
        .map((row, index) => `      <tr>
        <td class="num">${index + 1}</td>
        <td>${escapeHtml(row.customer)}</td>
        <td class="num">${money(row.previous)}</td>
        <td class="num">${money(row.debit)}</td>
        <td class="num">${money(row.credit)}</td>
        <td class="num">${money(row.balance)}</td>
      </tr>`)
        .join('\n');
    const empty = ar ? 'لا توجد مديونية في هذه الفترة' : 'No debt in this period';
    const body = `    <section class="meta">
      <div><span class="label">${ar ? 'المندوب' : 'Salesperson'}</span><span class="value">${escapeHtml(report.salesperson.name)}</span></div>
      <div><span class="label">${ar ? 'من' : 'From'}</span><span class="value">${escapeHtml(formatDate(report.from))}</span></div>
      <div><span class="label">${ar ? 'إلى' : 'To'}</span><span class="value">${escapeHtml(formatDate(report.to))}</span></div>
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
    return renderPage({
        title: ar ? 'مديونية عملاء المندوب' : 'Salesperson customer debt',
        company: settings,
        showCompanyDetails: false,
        body,
        dir: ar ? 'rtl' : 'ltr',
        lang,
    });
}
/** Collection receipts grouped by the cash box that received the money. */
function collectionsByBoxHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const sections = report.boxes
        .map((box) => {
        const rows = box.vouchers
            .map((voucher) => `      <tr>
        <td>${escapeHtml(formatDate(voucher.collectedAt))}</td>
        <td>${escapeHtml(voucher.number)}</td>
        <td>${escapeHtml(voucher.salesperson ?? '—')}</td>
        <td>${escapeHtml(voucher.lines.map((line) => line.customer ?? '—').join('، '))}</td>
        <td class="num">${money(voucher.total)}</td>
      </tr>`)
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
function expenseCategoryStatementHtml(report, categoryName, settings, lang = 'en') {
    const ar = isArabic(lang);
    const rows = report.expenses
        .map((expense) => `      <tr>
        <td>${escapeHtml(formatDate(expense.spentAt))}</td>
        <td>${escapeHtml(expense.number)}</td>
        <td>${escapeHtml(expense.payee ?? '—')}</td>
        <td>${escapeHtml(expense.cashBox?.name ?? '—')}</td>
        <td>${escapeHtml(expense.note ?? expense.reference ?? '—')}</td>
        <td class="num">${money(expense.amount)}</td>
      </tr>`)
        .join('\n');
    const empty = ar ? 'لا توجد مصروفات في هذه الفترة' : 'No expenses in this period';
    const body = `    <section class="meta">
      <div><span class="label">${ar ? 'البند' : 'Category'}</span><span class="value">${escapeHtml(categoryName)}</span></div>
      <div><span class="label">${ar ? 'عدد المصروفات' : 'Entries'}</span><span class="value">${escapeHtml(report.count)}</span></div>
      <div><span class="label">${ar ? 'الإجمالي' : 'Total'}</span><span class="value">${money(report.total)}</span></div>
      <div><span class="label">${ar ? 'الفترة' : 'Period'}</span><span class="value">${escapeHtml(formatDate(report.from))} → ${escapeHtml(formatDate(report.to))}</span></div>
    </section>
    <table class="data">
      <thead>
        <tr>
          <th>${ar ? 'التاريخ' : 'Date'}</th>
          <th>${ar ? 'الرقم' : 'Number'}</th>
          <th>${ar ? 'المستفيد' : 'Payee'}</th>
          <th>${ar ? 'الخزنة' : 'Cash box'}</th>
          <th>${ar ? 'ملاحظات' : 'Notes'}</th>
          <th class="num">${ar ? 'المبلغ' : 'Amount'}</th>
        </tr>
      </thead>
      <tbody>
${rows || `        <tr><td colspan="6" class="muted center">${empty}</td></tr>`}
        <tr class="total"><td colspan="5">${ar ? 'الإجمالي' : 'Total'}</td><td class="num">${money(report.total)}</td></tr>
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
function orderFulfilmentHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const sections = report.rows
        .map((order) => {
        const rows = order.lines
            .map((line) => `      <tr>
        <td>${escapeHtml(line.sku)}</td>
        <td>${escapeHtml(line.name)}</td>
        <td class="num">${escapeHtml(line.required)}</td>
        <td class="num">${escapeHtml(line.available)}</td>
        <td class="num">${escapeHtml(line.shortage)}</td>
      </tr>`)
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
function settlementsStatementHtml(report, settings, lang = 'en') {
    const ar = isArabic(lang);
    const rows = report.rows
        .map((row) => `      <tr>
        <td>${escapeHtml(formatDate(row.settledAt))}</td>
        <td>${escapeHtml(row.number)}</td>
        <td>${escapeHtml(row.target)}</td>
        <td>${escapeHtml(row.accountName || '—')}</td>
        <td>${escapeHtml(row.direction === 'INCREASE'
        ? ar
            ? 'زيادة'
            : 'Increase'
        : ar
            ? 'خصم'
            : 'Decrease')}</td>
        <td class="num">${money(row.amount)}</td>
        <td>${escapeHtml(row.note ?? row.reference ?? '—')}</td>
      </tr>`)
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
//# sourceMappingURL=printing.templates.js.map