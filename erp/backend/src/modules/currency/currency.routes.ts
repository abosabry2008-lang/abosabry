import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, noContent, ok } from '../../lib/http';
import { authenticate } from '../../middleware/authenticate';
import { requirePermission, requireAdmin } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';

const router = Router();
router.use(authenticate);

const createSchema = z.object({
  code: z.string().min(1).max(8),
  name: z.string().min(1),
  symbol: z.string().min(1).default('$'),
  exchangeRate: z.number().positive().default(1),
  isBase: z.boolean().default(false),
  active: z.boolean().default(true),
});

const updateSchema = z.object({
  code: z.string().min(1).max(8).optional(),
  name: z.string().min(1).optional(),
  symbol: z.string().min(1).optional(),
  exchangeRate: z.number().positive().optional(),
  isBase: z.boolean().optional(),
  active: z.boolean().optional(),
});

router.get(
  '/',
  requirePermission('currency.read'),
  asyncHandler(async (_req, res) => {
    const currencies = await prisma.currency.findMany({ orderBy: [{ isBase: 'desc' }, { code: 'asc' }] });
    ok(res, currencies);
  }),
);

router.post(
  '/',
  requirePermission('currency.write'),
  validateBody(createSchema),
  asyncHandler(async (req, res) => {
    const { isBase, ...rest } = req.body;
    const currency = await prisma.$transaction(async (tx) => {
      if (isBase) {
        await tx.currency.updateMany({ data: { isBase: false } });
      }
      return tx.currency.create({
        data: { ...rest, isBase: Boolean(isBase), exchangeRate: isBase ? 1 : rest.exchangeRate },
      });
    });
    created(res, currency);
  }),
);

router.patch(
  '/:id',
  requirePermission('currency.write'),
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    const { isBase, ...rest } = req.body;
    const currency = await prisma.$transaction(async (tx) => {
      if (isBase) {
        await tx.currency.updateMany({ data: { isBase: false } });
      }
      return tx.currency.update({
        where: { id: req.params.id },
        data: { ...rest, ...(isBase === undefined ? {} : { isBase }), ...(isBase ? { exchangeRate: 1 } : {}) },
      });
    });
    ok(res, currency);
  }),
);

router.delete(
  '/:id',
  requirePermission('currency.write'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const currency = await prisma.currency.findUnique({ where: { id: req.params.id } });
    if (!currency) throw ApiError.notFound('Currency not found');
    if (currency.isBase) throw ApiError.badRequest('The base currency cannot be deleted');
    await prisma.currency.delete({ where: { id: req.params.id } });
    noContent(res);
  }),
);

export default router;
