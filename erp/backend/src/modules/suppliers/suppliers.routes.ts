import { Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, getPaging, noContent, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asBool, asString } from '../../lib/query';
import { authenticate } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';

const router = Router();
router.use(authenticate);

const schema = z.object({
  name: z.string().min(1),
  contact: z.string().nullable().optional(),
  email: z.string().email().nullable().optional(),
  phone: z.string().nullable().optional(),
  address: z.string().nullable().optional(),
  taxId: z.string().nullable().optional(),
  paymentTermDays: z.number().int().min(0).default(30),
  active: z.boolean().default(true),
});

router.get(
  '/',
  requirePermission('purchasing.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 50);
    const search = asString(query.search);
    const active = asBool(query.active);

    const where: Prisma.SupplierWhereInput = {
      ...(search
        ? {
            OR: [
              { name: { contains: search, mode: 'insensitive' } },
              { email: { contains: search, mode: 'insensitive' } },
              { phone: { contains: search, mode: 'insensitive' } },
            ],
          }
        : {}),
      ...(active === undefined ? {} : { active }),
    };

    const [total, suppliers] = await Promise.all([
      prisma.supplier.count({ where }),
      prisma.supplier.findMany({
        where,
        orderBy: { name: 'asc' },
        skip: paging.skip,
        take: paging.take,
        include: { _count: { select: { purchaseOrders: true } } },
      }),
    ]);
    paginated(res, suppliers, total, paging);
  }),
);

router.get(
  '/:id',
  requirePermission('purchasing.read'),
  asyncHandler(async (req, res) => {
    const supplier = await prisma.supplier.findUnique({
      where: { id: req.params.id },
      include: { _count: { select: { purchaseOrders: true } } },
    });
    if (!supplier) throw ApiError.notFound('Supplier not found');
    ok(res, supplier);
  }),
);

router.post(
  '/',
  requirePermission('purchasing.write'),
  validateBody(schema),
  asyncHandler(async (req, res) => {
    const supplier = await prisma.supplier.create({ data: req.body });
    created(res, supplier);
  }),
);

router.patch(
  '/:id',
  requirePermission('purchasing.write'),
  validateBody(schema.partial()),
  asyncHandler(async (req, res) => {
    const supplier = await prisma.supplier.update({ where: { id: req.params.id }, data: req.body });
    ok(res, supplier);
  }),
);

router.delete(
  '/:id',
  requirePermission('purchasing.write'),
  asyncHandler(async (req, res) => {
    const orders = await prisma.purchaseOrder.count({ where: { supplierId: req.params.id } });
    if (orders > 0) {
      await prisma.supplier.update({ where: { id: req.params.id }, data: { active: false } });
      noContent(res);
      return;
    }
    await prisma.supplier.delete({ where: { id: req.params.id } });
    noContent(res);
  }),
);

export default router;
