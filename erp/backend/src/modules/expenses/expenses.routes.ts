import { PaymentMethod } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, created, getPaging, ok } from '../../lib/http';
import { asBool, asDate, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission, requireAdmin } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';
import {
  buildExpenseReport,
  cancelExpense,
  createExpense,
  createExpenseCategory,
  deleteExpenseCategory,
  listExpenseCategories,
  listExpenses,
  updateExpense,
  updateExpenseCategory,
} from './expenses.service';

const router = Router();
router.use(authenticate);

const methods: PaymentMethod[] = ['CASH', 'CARD', 'BANK_TRANSFER', 'MOBILE_MONEY', 'CHEQUE', 'OTHER'];

const categorySchema = z.object({
  name: z.string().min(1).max(120),
  accountCode: z.string().nullable().optional(),
  active: z.boolean().optional(),
});

const categoryUpdateSchema = categorySchema.partial();

const expenseSchema = z.object({
  categoryId: z.string().nullable().optional(),
  cashBoxId: z.string().nullable().optional(),
  amount: z
    .number()
    .refine((value) => value !== 0, { message: 'Amount cannot be zero' }),
  method: z.nativeEnum(PaymentMethod).optional(),
  payee: z.string().nullable().optional(),
  reference: z.string().nullable().optional(),
  note: z.string().nullable().optional(),
  spentAt: z.coerce.date().nullable().optional(),
});

const expenseUpdateSchema = expenseSchema.partial();

interface ExpenseMoney {
  amount: unknown;
}

const serializeExpense = <T extends ExpenseMoney>(expense: T) => ({
  ...expense,
  amount: Number(expense.amount),
});

// --- expense categories -----------------------------------------------------

router.get(
  '/categories',
  requirePermission('expenses.read'),
  asyncHandler(async (_req, res) => {
    ok(res, await listExpenseCategories());
  }),
);

router.post(
  '/categories',
  requirePermission('expenses.write'),
  validateBody(categorySchema),
  asyncHandler(async (req, res) => {
    const category = await createExpenseCategory(req.body);
    created(res, category);
  }),
);

router.patch(
  '/categories/:id',
  requirePermission('expenses.write'),
  validateBody(categoryUpdateSchema),
  asyncHandler(async (req, res) => {
    const category = await updateExpenseCategory(req.params.id, req.body);
    ok(res, category);
  }),
);

router.delete(
  '/categories/:id',
  requirePermission('expenses.write'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const result = await deleteExpenseCategory(req.params.id);
    ok(res, result);
  }),
);

// --- expenses ---------------------------------------------------------------

router.get(
  '/',
  requirePermission('expenses.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 25);
    const includeCancelled = asBool(query.includeCancelled) === true;
    const from = asDate(query.from);
    const to = asDate(query.to);
    const categoryId = asString(query.categoryId);
    const cashBoxId = asString(query.cashBoxId);
    const search = asString(query.search);

    const result = await listExpenses({
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
  }),
);

router.post(
  '/',
  requirePermission('expenses.write'),
  validateBody(expenseSchema),
  asyncHandler(async (req, res) => {
    const expense = await createExpense({ ...req.body, userId: currentUser(req).id });
    created(res, serializeExpense(expense));
  }),
);

router.patch(
  '/:id',
  requirePermission('expenses.write'),
  validateBody(expenseUpdateSchema),
  asyncHandler(async (req, res) => {
    const expense = await updateExpense(req.params.id, req.body, currentUser(req).id);
    ok(res, serializeExpense(expense));
  }),
);

router.post(
  '/:id/cancel',
  requirePermission('expenses.write'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const expense = await cancelExpense(req.params.id, currentUser(req).id);
    ok(res, serializeExpense(expense));
  }),
);

// --- report -----------------------------------------------------------------

router.get(
  '/report',
  requirePermission('expenses.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const report = await buildExpenseReport({
      from: asDate(query.from),
      to: asDate(query.to),
      categoryId: asString(query.categoryId),
      cashBoxId: asString(query.cashBoxId),
    });
    ok(res, report);
  }),
);

export default router;
