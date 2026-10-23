"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const client_1 = require("@prisma/client");
const express_1 = require("express");
const zod_1 = require("zod");
const http_1 = require("../../lib/http");
const query_1 = require("../../lib/query");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const expenses_service_1 = require("./expenses.service");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const methods = ['CASH', 'CARD', 'BANK_TRANSFER', 'MOBILE_MONEY', 'CHEQUE', 'OTHER'];
const categorySchema = zod_1.z.object({
    name: zod_1.z.string().min(1).max(120),
    accountCode: zod_1.z.string().nullable().optional(),
    active: zod_1.z.boolean().optional(),
});
const categoryUpdateSchema = categorySchema.partial();
const expenseSchema = zod_1.z.object({
    categoryId: zod_1.z.string().nullable().optional(),
    cashBoxId: zod_1.z.string().nullable().optional(),
    amount: zod_1.z
        .number()
        .refine((value) => value !== 0, { message: 'Amount cannot be zero' }),
    method: zod_1.z.nativeEnum(client_1.PaymentMethod).optional(),
    payee: zod_1.z.string().nullable().optional(),
    reference: zod_1.z.string().nullable().optional(),
    note: zod_1.z.string().nullable().optional(),
    spentAt: zod_1.z.coerce.date().nullable().optional(),
});
const expenseUpdateSchema = expenseSchema.partial();
const serializeExpense = (expense) => ({
    ...expense,
    amount: Number(expense.amount),
});
// --- expense categories -----------------------------------------------------
router.get('/categories', (0, authorize_1.requirePermission)('expenses.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    (0, http_1.ok)(res, await (0, expenses_service_1.listExpenseCategories)());
}));
router.post('/categories', (0, authorize_1.requirePermission)('expenses.write'), (0, validate_1.validateBody)(categorySchema), (0, http_1.asyncHandler)(async (req, res) => {
    const category = await (0, expenses_service_1.createExpenseCategory)(req.body);
    (0, http_1.created)(res, category);
}));
router.patch('/categories/:id', (0, authorize_1.requirePermission)('expenses.write'), (0, validate_1.validateBody)(categoryUpdateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const category = await (0, expenses_service_1.updateExpenseCategory)(req.params.id, req.body);
    (0, http_1.ok)(res, category);
}));
router.delete('/categories/:id', (0, authorize_1.requirePermission)('expenses.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const result = await (0, expenses_service_1.deleteExpenseCategory)(req.params.id);
    (0, http_1.ok)(res, result);
}));
// --- expenses ---------------------------------------------------------------
router.get('/', (0, authorize_1.requirePermission)('expenses.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const paging = (0, http_1.getPaging)(query, 25);
    const includeCancelled = (0, query_1.asBool)(query.includeCancelled) === true;
    const from = (0, query_1.asDate)(query.from);
    const to = (0, query_1.asDate)(query.to);
    const categoryId = (0, query_1.asString)(query.categoryId);
    const cashBoxId = (0, query_1.asString)(query.cashBoxId);
    const search = (0, query_1.asString)(query.search);
    const result = await (0, expenses_service_1.listExpenses)({
        from,
        to,
        categoryId,
        cashBoxId,
        includeCancelled,
        search,
        skip: paging.skip,
        take: paging.take,
    });
    res.status(200).json({
        data: result.items.map(serializeExpense),
        meta: {
            page: paging.page,
            pageSize: paging.pageSize,
            total: result.total,
            totalPages: paging.take > 0 ? Math.ceil(result.total / paging.take) : 0,
            totalAmount: result.totalAmount,
        },
    });
}));
router.post('/', (0, authorize_1.requirePermission)('expenses.write'), (0, validate_1.validateBody)(expenseSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const expense = await (0, expenses_service_1.createExpense)({ ...req.body, userId: (0, authenticate_1.currentUser)(req).id });
    (0, http_1.created)(res, serializeExpense(expense));
}));
router.patch('/:id', (0, authorize_1.requirePermission)('expenses.write'), (0, validate_1.validateBody)(expenseUpdateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const expense = await (0, expenses_service_1.updateExpense)(req.params.id, req.body, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.ok)(res, serializeExpense(expense));
}));
router.post('/:id/cancel', (0, authorize_1.requirePermission)('expenses.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    const expense = await (0, expenses_service_1.cancelExpense)(req.params.id, (0, authenticate_1.currentUser)(req).id);
    (0, http_1.ok)(res, serializeExpense(expense));
}));
// --- report -----------------------------------------------------------------
router.get('/report', (0, authorize_1.requirePermission)('expenses.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const query = req.query;
    const report = await (0, expenses_service_1.buildExpenseReport)({
        from: (0, query_1.asDate)(query.from),
        to: (0, query_1.asDate)(query.to),
        categoryId: (0, query_1.asString)(query.categoryId),
        cashBoxId: (0, query_1.asString)(query.cashBoxId),
    });
    (0, http_1.ok)(res, report);
}));
exports.default = router;
//# sourceMappingURL=expenses.routes.js.map