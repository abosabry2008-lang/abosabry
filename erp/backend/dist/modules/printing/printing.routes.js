"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const api_error_1 = require("../../lib/api-error");
const http_1 = require("../../lib/http");
const prisma_1 = require("../../lib/prisma");
const query_1 = require("../../lib/query");
const money_1 = require("../../lib/money");
const settings_1 = require("../../lib/settings");
const authenticate_token_1 = require("../../middleware/authenticate-token");
const authorize_1 = require("../../middleware/authorize");
const invoices_service_1 = require("../invoices/invoices.service");
const reports_service_1 = require("../reports/reports.service");
const statement_service_1 = require("../reports/statement.service");
const analytics_service_1 = require("../reports/analytics.service");
const printing_templates_1 = require("./printing.templates");
const salespeople_service_1 = require("../reports/salespeople.service");
const collections_service_1 = require("../reports/collections.service");
const expenses_service_1 = require("../expenses/expenses.service");
const settlements_service_1 = require("../settlements/settlements.service");
const router = (0, express_1.Router)();
// Print pages are opened in a browser, so the access token may arrive either as
// an `Authorization: Bearer` header or as a `?token=` query parameter.
router.use(authenticate_token_1.authenticateToken);
function sendHtml(res, html) {
    res.set('Content-Type', 'text/html; charset=utf-8');
    res.send(html);
}
// GET /print/invoices/:id
router.get('/invoices/:id', (0, authorize_1.requirePermission)('invoices.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const [invoice, settings] = await Promise.all([
        prisma_1.prisma.invoice.findUnique({ where: { id: req.params.id }, include: invoices_service_1.invoiceInclude }),
        (0, settings_1.getSettings)(),
    ]);
    if (!invoice)
        throw api_error_1.ApiError.notFound('Invoice not found');
    // What the customer already owed before this invoice: their stored balance
    // minus this invoice's own outstanding balance (only issued invoices are
    // counted in the customer balance).
    let previousBalance = 0;
    if (invoice.customer) {
        const counted = ['ISSUED', 'PARTIALLY_PAID', 'PAID'].includes(invoice.status);
        previousBalance = (0, money_1.round2)(Number(invoice.customer.balance) - (counted ? Number(invoice.balance) : 0));
    }
    sendHtml(res, (0, printing_templates_1.invoiceHtml)(invoice, settings, {
        previousBalance,
        lang: (0, query_1.asString)(req.query.lang) ?? 'en',
    }));
}));
// GET /print/customers/:id/statement
router.get('/customers/:id/statement', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const [statement, settings] = await Promise.all([
        (0, statement_service_1.buildCustomerStatement)(req.params.id, from, to),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.customerStatementHtml)(statement, settings, (0, query_1.asString)(req.query.lang) ?? 'en'));
}));
// GET /print/suppliers/:id/statement
router.get('/suppliers/:id/statement', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const [statement, settings] = await Promise.all([
        (0, statement_service_1.buildSupplierStatement)(req.params.id, from, to),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.supplierStatementHtml)(statement, settings, (0, query_1.asString)(req.query.lang) ?? 'en'));
}));
// GET /print/reports/sales
router.get('/reports/sales', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const groupBy = (0, query_1.asString)(req.query.groupBy) === 'month' ? 'month' : 'day';
    const [report, settings] = await Promise.all([(0, reports_service_1.buildSalesReport)(from, to, groupBy), (0, settings_1.getSettings)()]);
    sendHtml(res, (0, printing_templates_1.salesReportHtml)(report, settings));
}));
// GET /print/reports/inventory-valuation
router.get('/reports/inventory-valuation', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouseId = (0, query_1.asString)(req.query.warehouseId);
    const [report, settings] = await Promise.all([
        (0, reports_service_1.buildInventoryValuation)(warehouseId),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.inventoryValuationHtml)(report, settings));
}));
// GET /print/reports/top-products
router.get('/reports/top-products', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const limit = Number((0, query_1.asString)(req.query.limit) ?? 10);
    const [report, settings] = await Promise.all([(0, reports_service_1.buildTopProducts)(from, to, limit), (0, settings_1.getSettings)()]);
    sendHtml(res, (0, printing_templates_1.topProductsHtml)(report, settings));
}));
// GET /print/reports/receivables-by-salesperson
router.get('/reports/receivables-by-salesperson', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const userId = (0, query_1.asString)(req.query.userId);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, analytics_service_1.buildReceivablesBySalesperson)(from, to, userId),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.receivablesBySalespersonHtml)(report, settings, lang));
}));
// GET /print/reports/supplier-payables
router.get('/reports/supplier-payables', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([(0, analytics_service_1.buildSupplierPayables)(from, to), (0, settings_1.getSettings)()]);
    sendHtml(res, (0, printing_templates_1.supplierPayablesHtml)(report, settings, lang));
}));
// GET /print/reports/stock-balance
router.get('/reports/stock-balance', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouseId = (0, query_1.asString)(req.query.warehouseId);
    const categoryId = (0, query_1.asString)(req.query.categoryId);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, analytics_service_1.buildStockBalance)(warehouseId, categoryId),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.stockBalanceHtml)(report, settings, lang));
}));
// GET /print/reports/item-movement
router.get('/reports/item-movement', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const productId = (0, query_1.asString)(req.query.productId);
    if (!productId)
        throw api_error_1.ApiError.badRequest('productId is required', 'PRODUCT_REQUIRED');
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const warehouseId = (0, query_1.asString)(req.query.warehouseId);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, analytics_service_1.buildItemMovement)(productId, from, to, warehouseId),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.itemMovementHtml)(report, settings, lang));
}));
// GET /print/reports/consolidated-sales-note
router.get('/reports/consolidated-sales-note', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const salespersonId = (0, query_1.asString)(req.query.salespersonId);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, salespeople_service_1.buildConsolidatedSalesNote)(from, to, salespersonId),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.consolidatedSalesNoteHtml)(report, settings, lang));
}));
// GET /print/reports/profit-by-salesperson
router.get('/reports/profit-by-salesperson', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const salespersonId = (0, query_1.asString)(req.query.salespersonId);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, salespeople_service_1.buildProfitBySalesperson)(from, to, salespersonId),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.profitBySalespersonHtml)(report, settings, lang));
}));
// GET /print/reports/collections-by-salesperson
router.get('/reports/collections-by-salesperson', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const salespersonId = (0, query_1.asString)(req.query.salespersonId);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, salespeople_service_1.buildCollectionsBySalesperson)(from, to, salespersonId),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.collectionsBySalespersonHtml)(report, settings, lang));
}));
// GET /print/salespeople/:id/statement
router.get('/salespeople/:id/statement', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [statement, settings] = await Promise.all([
        (0, salespeople_service_1.buildSalespersonStatement)(req.params.id, from, to),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.salespersonStatementHtml)(statement, settings, lang));
}));
// GET /print/reports/shortages
router.get('/reports/shortages', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouseId = (0, query_1.asString)(req.query.warehouseId);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, analytics_service_1.buildShortagesReport)(warehouseId),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.shortagesHtml)(report, settings, lang));
}));
// GET /print/salespeople/:id/customers
router.get('/salespeople/:id/customers', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, salespeople_service_1.buildSalespersonCustomerDebt)(req.params.id, from, to),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.salespersonCustomerDebtHtml)(report, settings, lang));
}));
// GET /print/reports/collections-by-box
router.get('/reports/collections-by-box', (0, authorize_1.requirePermission)('payments.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const cashBoxId = (0, query_1.asString)(req.query.cashBoxId);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, collections_service_1.buildCollectionsByBox)(from, to, cashBoxId),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.collectionsByBoxHtml)(report, settings, lang));
}));
// GET /print/reports/expenses/category/:id
router.get('/reports/expenses/category/:id', (0, authorize_1.requirePermission)('expenses.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const category = await prisma_1.prisma.expenseCategory.findUnique({
        where: { id: req.params.id },
        select: { name: true },
    });
    const [report, settings] = await Promise.all([
        (0, expenses_service_1.buildExpenseReport)({ from, to, categoryId: req.params.id }),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.expenseCategoryStatementHtml)(report, category?.name ?? '—', settings, lang));
}));
// GET /print/reports/order-fulfilment
router.get('/reports/order-fulfilment', (0, authorize_1.requirePermission)('reports.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const warehouseId = (0, query_1.asString)(req.query.warehouseId);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, analytics_service_1.buildOrderFulfilmentReport)(warehouseId),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.orderFulfilmentHtml)(report, settings, lang));
}));
// GET /print/reports/settlements
router.get('/reports/settlements', (0, authorize_1.requirePermission)('treasury.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, settlements_service_1.buildSettlementStatement)({ from, to }),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.settlementsStatementHtml)(report, settings, lang));
}));
// GET /print/reports/expenses
router.get('/reports/expenses', (0, authorize_1.requirePermission)('expenses.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const from = (0, query_1.asDate)(req.query.from);
    const to = (0, query_1.asDate)(req.query.to);
    const lang = (0, query_1.asString)(req.query.lang) ?? 'en';
    const [report, settings] = await Promise.all([
        (0, expenses_service_1.buildExpenseReport)({ from, to }),
        (0, settings_1.getSettings)(),
    ]);
    sendHtml(res, (0, printing_templates_1.expenseReportHtml)(report, settings, lang));
}));
exports.default = router;
//# sourceMappingURL=printing.routes.js.map