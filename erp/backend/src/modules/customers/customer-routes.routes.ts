import { Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, getPaging, noContent, ok, paginated } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { asBool, asString } from '../../lib/query';
import { authenticate } from '../../middleware/authenticate';
import { requirePermission, requireAdmin } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';

const router = Router();
router.use(authenticate);

const schema = z.object({
  code: z.string().max(64).nullable().optional(),
  name: z.string().min(1),
  salespersonId: z.string().nullable().optional(),
  active: z.boolean().default(true),
  notes: z.string().nullable().optional(),
});

const include = {
  salesperson: { select: { id: true, name: true } },
  _count: { select: { customers: true } },
} satisfies Prisma.CustomerRouteInclude;

const serialize = <T>(route: T) => route;

/** When a route is assigned to a representative, its customers follow. */
async function syncRouteCustomers(routeId: string): Promise<number> {
  const route = await prisma.customerRoute.findUnique({
    where: { id: routeId },
    select: { salespersonId: true },
  });
  if (!route?.salespersonId) return 0;
  const result = await prisma.customer.updateMany({
    where: { routeId },
    data: { salespersonId: route.salespersonId },
  });
  return result.count;
}

router.get(
  '/',
  requirePermission('customers.read'),
  asyncHandler(async (req, res) => {
    const query = req.query as Record<string, unknown>;
    const paging = getPaging(query, 100);
    const search = asString(query.search);
    const active = asBool(query.active);
    const where: Prisma.CustomerRouteWhereInput = {
      ...(active === undefined ? {} : { active }),
      ...(search
        ? {
            OR: [
              { name: { contains: search, mode: 'insensitive' } },
              { code: { contains: search, mode: 'insensitive' } },
            ],
          }
        : {}),
    };
    const [total, rows] = await Promise.all([
      prisma.customerRoute.count({ where }),
      prisma.customerRoute.findMany({
        where,
        include,
        orderBy: { name: 'asc' },
        skip: paging.skip,
        take: paging.take,
      }),
    ]);
    paginated(res, rows.map(serialize), total, paging);
  }),
);

router.post(
  '/',
  requirePermission('customers.write'),
  validateBody(schema),
  asyncHandler(async (req, res) => {
    const route = await prisma.customerRoute.create({
      data: req.body,
      include,
    });
    await syncRouteCustomers(route.id);
    const refreshed = await prisma.customerRoute.findUniqueOrThrow({
      where: { id: route.id },
      include,
    });
    created(res, serialize(refreshed));
  }),
);

router.patch(
  '/:id',
  requirePermission('customers.write'),
  validateBody(schema.partial()),
  asyncHandler(async (req, res) => {
    await prisma.customerRoute.update({
      where: { id: req.params.id },
      data: req.body,
    });
    await syncRouteCustomers(req.params.id);
    const route = await prisma.customerRoute.findUnique({
      where: { id: req.params.id },
      include,
    });
    if (!route) throw ApiError.notFound('Route not found');
    ok(res, serialize(route));
  }),
);

// Re-applies the route's salesperson to every customer on it.
router.post(
  '/:id/apply',
  requirePermission('customers.write'),
  asyncHandler(async (req, res) => {
    const count = await syncRouteCustomers(req.params.id);
    ok(res, { count });
  }),
);

router.delete(
  '/:id',
  requirePermission('customers.write'),
  requireAdmin(),
  asyncHandler(async (req, res) => {
    const customers = await prisma.customer.count({ where: { routeId: req.params.id } });
    if (customers > 0) {
      await prisma.customerRoute.update({
        where: { id: req.params.id },
        data: { active: false },
      });
    } else {
      await prisma.customerRoute.delete({ where: { id: req.params.id } });
    }
    noContent(res);
  }),
);

export default router;
