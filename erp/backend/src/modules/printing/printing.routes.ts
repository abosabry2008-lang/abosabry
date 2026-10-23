import type { Response } from 'express';
import { Router } from 'express';
import { ApiError } from '../../lib/api-error';
import { asyncHandler } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asDate, asString } from '../../lib/query';
import { round2 } from '../../lib/money';
import { getSettings } from '../../lib/settings';
import { authenticateToken } from '../../middleware/authenticate-token';
import { requirePermission } from '../../middleware/authorize';
import { invoiceInclude } from '../invoices/invoices.service';
import {
  buildInventoryValuation,
  buildSalesReport,
  buildTopProducts,
  type SalesGroupBy,
} from '../reports/reports.service';
import { buildCustomerStatement, buildSupplierStatement } from '../reports/statement.service';
import {
  buildItemMovement,
  buildOrderFulfilmentReport,
  buildReceivablesBySalesperson,
  buildShortagesReport,
  buildStockBalance,
  buildSupplierPayables,
} from '../reports/analytics.service';
import {
  customerStatementHtml,
  inventoryValuationHtml,
  invoiceHtml,
  itemMovementHtml,
  receivablesBySalespersonHtml,
  salesReportHtml,
  stockBalanceHtml,
  supplierPayablesHtml,
  supplierStatementHtml,
  topProductsHtml,
  collectionsBySalespersonHtml,
  consolidatedSalesNoteHtml,
  expenseReportHtml,
  profitBySalespersonHtml,
  salespersonStatementHtml,
  salespersonCustomerDebtHtml,
  shortagesHtml,
  collectionsByBoxHtml,
  expenseCategoryStatementHtml,
  orderFulfilmentHtml,
  settlementsStatementHtml,
} from './printing.templates';
import {
  buildCollectionsBySalesperson,
  buildConsolidatedSalesNote,
  buildProfitBySalesperson,
  buildSalespersonCustomerDebt,
  buildSalespersonStatement,
} from '../reports/salespeople.service';
import { buildCollectionsByBox } from '../reports/collections.service';
import { buildExpenseReport } from '../expenses/expenses.service';
import { buildSettlementStatement } from '../settlements/settlements.service';

const router = Router();

// Print pages are opened in a browser, so the access token may arrive either as
// an `Authorization: Bearer` header or as a `?token=` query parameter.
router.use(authenticateToken);

function sendHtml(res: Response, html: string): void {
  res.set('Content-Type', 'text/html; charset=utf-8');
  res.send(html);
}

// GET /print/invoices/:id
router.get(
  '/invoices/:id',
  requirePermission('invoices.read'),
  asyncHandler(async (req, res) => {
    const [invoice, settings] = await Promise.all([
      prisma.invoice.findUnique({ where: { id: req.params.id }, include: invoiceInclude }),
      getSettings(),
    ]);
    if (!invoice) throw ApiError.notFound('Invoice not found');

    // What the customer already owed before this invoice: their stored balance
    // minus this invoice's own outstanding balance (only issued invoices are
    // counted in the customer balance).
    let previousBalance = 0;
    if (invoice.customer) {
      const counted = ['ISSUED', 'PARTIALLY_PAID', 'PAID'].includes(invoice.status);
      previousBalance = round2(
        Number(invoice.customer.balance) - (counted ? Number(invoice.balance) : 0),
      );
    }

    sendHtml(res, invoiceHtml(invoice, settings, {
      previousBalance,
      lang: asString(req.query.lang) ?? 'en',
    }));
  }),
);

// GET /print/customers/:id/statement
router.get(
  '/customers/:id/statement',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const [statement, settings] = await Promise.all([
      buildCustomerStatement(req.params.id, from, to),
      getSettings(),
    ]);
    sendHtml(res, customerStatementHtml(statement, settings, asString(req.query.lang) ?? 'en'));
  }),
);

// GET /print/suppliers/:id/statement
router.get(
  '/suppliers/:id/statement',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const [statement, settings] = await Promise.all([
      buildSupplierStatement(req.params.id, from, to),
      getSettings(),
    ]);
    sendHtml(res, supplierStatementHtml(statement, settings, asString(req.query.lang) ?? 'en'));
  }),
);

// GET /print/reports/sales
router.get(
  '/reports/sales',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const groupBy: SalesGroupBy = asString(req.query.groupBy) === 'month' ? 'month' : 'day';
    const [report, settings] = await Promise.all([buildSalesReport(from, to, groupBy), getSettings()]);
    sendHtml(res, salesReportHtml(report, settings));
  }),
);

// GET /print/reports/inventory-valuation
router.get(
  '/reports/inventory-valuation',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const warehouseId = asString(req.query.warehouseId);
    const [report, settings] = await Promise.all([
      buildInventoryValuation(warehouseId),
      getSettings(),
    ]);
    sendHtml(res, inventoryValuationHtml(report, settings));
  }),
);

// GET /print/reports/top-products
router.get(
  '/reports/top-products',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const limit = Number(asString(req.query.limit) ?? 10);
    const [report, settings] = await Promise.all([buildTopProducts(from, to, limit), getSettings()]);
    sendHtml(res, topProductsHtml(report, settings));
  }),
);

// GET /print/reports/receivables-by-salesperson
router.get(
  '/reports/receivables-by-salesperson',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const userId = asString(req.query.userId);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
      buildReceivablesBySalesperson(from, to, userId),
      getSettings(),
    ]);
    sendHtml(res, receivablesBySalespersonHtml(report, settings, lang));
  }),
);

// GET /print/reports/supplier-payables
router.get(
  '/reports/supplier-payables',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([buildSupplierPayables(from, to), getSettings()]);
    sendHtml(res, supplierPayablesHtml(report, settings, lang));
  }),
);

// GET /print/reports/stock-balance
router.get(
  '/reports/stock-balance',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const warehouseId = asString(req.query.warehouseId);
    const categoryId = asString(req.query.categoryId);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
      buildStockBalance(warehouseId, categoryId),
      getSettings(),
    ]);
    sendHtml(res, stockBalanceHtml(report, settings, lang));
  }),
);

// GET /print/reports/item-movement
router.get(
  '/reports/item-movement',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const productId = asString(req.query.productId);
    if (!productId) throw ApiError.badRequest('productId is required', 'PRODUCT_REQUIRED');
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const warehouseId = asString(req.query.warehouseId);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
      buildItemMovement(productId, from, to, warehouseId),
      getSettings(),
    ]);
    sendHtml(res, itemMovementHtml(report, settings, lang));
  }),
);

// GET /print/reports/consolidated-sales-note
router.get(
  '/reports/consolidated-sales-note',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const salespersonId = asString(req.query.salespersonId);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
      buildConsolidatedSalesNote(from, to, salespersonId),
      getSettings(),
    ]);
    sendHtml(res, consolidatedSalesNoteHtml(report, settings, lang));
  }),
);

// GET /print/reports/profit-by-salesperson
router.get(
  '/reports/profit-by-salesperson',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const salespersonId = asString(req.query.salespersonId);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
      buildProfitBySalesperson(from, to, salespersonId),
      getSettings(),
    ]);
    sendHtml(res, profitBySalespersonHtml(report, settings, lang));
  }),
);

// GET /print/reports/collections-by-salesperson
router.get(
  '/reports/collections-by-salesperson',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const salespersonId = asString(req.query.salespersonId);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
      buildCollectionsBySalesperson(from, to, salespersonId),
      getSettings(),
    ]);
    sendHtml(res, collectionsBySalespersonHtml(report, settings, lang));
  }),
);

// GET /print/salespeople/:id/statement
router.get(
  '/salespeople/:id/statement',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const lang = asString(req.query.lang) ?? 'en';
    const [statement, settings] = await Promise.all([
      buildSalespersonStatement(req.params.id, from, to),
      getSettings(),
    ]);
    sendHtml(res, salespersonStatementHtml(statement, settings, lang));
  }),
);

// GET /print/reports/shortages
router.get(
  '/reports/shortages',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const warehouseId = asString(req.query.warehouseId);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
      buildShortagesReport(warehouseId),
      getSettings(),
    ]);
    sendHtml(res, shortagesHtml(report, settings, lang));
  }),
);

// GET /print/salespeople/:id/customers
router.get(
  '/salespeople/:id/customers',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const lang = asString(req.query.lang) ?? 'en';
    const rawFilter = asString(req.query.filter);
    const filter =
      rawFilter === 'debtors' || rawFilter === 'creditors' ? rawFilter : 'all';
    const [report, settings] = await Promise.all([
      buildSalespersonCustomerDebt(req.params.id, from, to, filter),
      getSettings(),
    ]);
    sendHtml(res, salespersonCustomerDebtHtml(report, settings, lang));
  }),
);

// GET /print/reports/collections-by-box
router.get(
  '/reports/collections-by-box',
  requirePermission('payments.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const cashBoxId = asString(req.query.cashBoxId);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
      buildCollectionsByBox(from, to, cashBoxId),
      getSettings(),
    ]);
    sendHtml(res, collectionsByBoxHtml(report, settings, lang));
  }),
);

// GET /print/reports/expenses/category/:id
router.get(
  '/reports/expenses/category/:id',
  requirePermission('expenses.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const lang = asString(req.query.lang) ?? 'en';
    const category = await prisma.expenseCategory.findUnique({
      where: { id: req.params.id },
      select: { name: true },
    });
    const [report, settings] = await Promise.all([
      buildExpenseReport({ from, to, categoryId: req.params.id }),
      getSettings(),
    ]);
    sendHtml(
      res,
      expenseCategoryStatementHtml(report, category?.name ?? '—', settings, lang),
    );
  }),
);

// GET /print/reports/order-fulfilment
router.get(
  '/reports/order-fulfilment',
  requirePermission('reports.read'),
  asyncHandler(async (req, res) => {
    const warehouseId = asString(req.query.warehouseId);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
      buildOrderFulfilmentReport(warehouseId),
      getSettings(),
    ]);
    sendHtml(res, orderFulfilmentHtml(report, settings, lang));
  }),
);

// GET /print/reports/settlements
router.get(
  '/reports/settlements',
  requirePermission('treasury.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
      buildSettlementStatement({ from, to }),
      getSettings(),
    ]);
    sendHtml(res, settlementsStatementHtml(report, settings, lang));
  }),
);

// GET /print/reports/expenses
router.get(
  '/reports/expenses',
  requirePermission('expenses.read'),
  asyncHandler(async (req, res) => {
    const from = asDate(req.query.from);
    const to = asDate(req.query.to);
    const lang = asString(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
      buildExpenseReport({ from, to }),
      getSettings(),
    ]);
    sendHtml(res, expenseReportHtml(report, settings, lang));
  }),
);

export default router;
