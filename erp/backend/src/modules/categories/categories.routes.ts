import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, noContent, ok } from '../../lib/http';
import { authenticate } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';

const router = Router();
router.use(authenticate);

const createSchema = z.object({
  name: z.string().min(1),
  description: z.string().nullable().optional(),
});

const updateSchema = createSchema.partial();

router.get(
  '/',
  requirePermission('categories.read'),
  asyncHandler(async (_req, res) => {
    const categories = await prisma.category.findMany({
      orderBy: { name: 'asc' },
      include: { _count: { select: { products: true } } },
    });
    ok(res, categories);
  }),
);

router.post(
  '/',
  requirePermission('categories.write'),
  validateBody(createSchema),
  asyncHandler(async (req, res) => {
    const category = await prisma.category.create({ data: req.body });
    created(res, category);
  }),
);

router.patch(
  '/:id',
  requirePermission('categories.write'),
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    const category = await prisma.category.update({ where: { id: req.params.id }, data: req.body });
    ok(res, category);
  }),
);

router.delete(
  '/:id',
  requirePermission('categories.write'),
  asyncHandler(async (req, res) => {
    const products = await prisma.product.count({ where: { categoryId: req.params.id, deletedAt: null } });
    if (products > 0) {
      throw ApiError.conflict(`Cannot delete: ${products} product(s) still use this category`);
    }
    await prisma.category.delete({ where: { id: req.params.id } });
    noContent(res);
  }),
);

export default router;
