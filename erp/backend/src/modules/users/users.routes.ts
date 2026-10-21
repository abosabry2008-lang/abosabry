import { Prisma, Role } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, created, getPaging, noContent, ok, paginated } from '../../lib/http';
import { hashPassword } from '../../lib/password';
import { ROLE_PERMISSIONS, roleHasPermission } from '../../lib/permissions';
import { asBool, asString } from '../../lib/query';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { requirePermission } from '../../middleware/authorize';
import { validateBody } from '../../middleware/validate';

const router = Router();
router.use(authenticate);

const roleEnum = z.nativeEnum(Role);

const createSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8, 'Password must be at least 8 characters'),
  name: z.string().min(1),
  role: roleEnum.default('SALES'),
  phone: z.string().nullable().optional(),
  active: z.boolean().optional(),
  permissions: z.array(z.string()).nullable().optional(),
});

const updateSchema = z.object({
  email: z.string().email().optional(),
  password: z.string().min(8).optional(),
  name: z.string().min(1).optional(),
  role: roleEnum.optional(),
  phone: z.string().nullable().optional(),
  active: z.boolean().optional(),
  permissions: z.array(z.string()).nullable().optional(),
});

const select = {
  id: true,
  email: true,
  name: true,
  role: true,
  phone: true,
  active: true,
  permissions: true,
  lastLoginAt: true,
  createdAt: true,
  updatedAt: true,
};

router.get(
  '/',
  requirePermission('users.read'),
  asyncHandler(async (req, res) => {
    const paging = getPaging(req.query as Record<string, unknown>);
    const search = asString(req.query.search);
    const role = asString(req.query.role) as Role | undefined;
    const active = asBool(req.query.active);

    const where = {
      ...(search
        ? {
            OR: [
              { name: { contains: search, mode: 'insensitive' as const } },
              { email: { contains: search, mode: 'insensitive' as const } },
            ],
          }
        : {}),
      ...(role ? { role } : {}),
      ...(active === undefined ? {} : { active }),
    };

    const [total, users] = await Promise.all([
      prisma.user.count({ where }),
      prisma.user.findMany({ where, select, orderBy: { name: 'asc' }, skip: paging.skip, take: paging.take }),
    ]);
    paginated(res, users, total, paging);
  }),
);

router.get(
  '/salespersons',
  requirePermission('customers.read'),
  asyncHandler(async (_req, res) => {
    const roles = (Object.keys(ROLE_PERMISSIONS) as Role[]).filter((role) =>
      roleHasPermission(role, 'sales.write'),
    );
    const users = await prisma.user.findMany({
      where: { active: true, role: { in: roles } },
      select: { id: true, name: true, email: true, role: true },
      orderBy: { name: 'asc' },
    });
    ok(res, users);
  }),
);

router.get(
  '/:id',
  requirePermission('users.read'),
  asyncHandler(async (req, res) => {
    const user = await prisma.user.findUnique({ where: { id: req.params.id }, select });
    if (!user) throw ApiError.notFound('User not found');
    ok(res, user);
  }),
);

router.post(
  '/',
  requirePermission('users.write'),
  validateBody(createSchema),
  asyncHandler(async (req, res) => {
    const user = await prisma.user.create({
      data: {
        email: String(req.body.email).toLowerCase(),
        passwordHash: await hashPassword(String(req.body.password)),
        name: req.body.name,
        role: req.body.role,
        phone: req.body.phone ?? null,
        active: req.body.active ?? true,
        ...(req.body.permissions !== undefined ? { permissions: req.body.permissions as any } : {}),
      } as any,
      select,
    });
    created(res, user);
  }),
);

router.patch(
  '/:id',
  requirePermission('users.write'),
  validateBody(updateSchema),
  asyncHandler(async (req, res) => {
    const data: Prisma.UserUpdateInput = {};
    if (req.body.email !== undefined) data.email = String(req.body.email).toLowerCase();
    if (req.body.name !== undefined) data.name = req.body.name;
    if (req.body.role !== undefined) data.role = req.body.role;
    if (req.body.phone !== undefined) data.phone = req.body.phone;
    if (req.body.active !== undefined) data.active = req.body.active;
    if (req.body.permissions !== undefined) (data as any).permissions = req.body.permissions;
    if (req.body.password) data.passwordHash = await hashPassword(String(req.body.password));

    const user = await prisma.user.update({ where: { id: req.params.id }, data, select });
    ok(res, user);
  }),
);

router.delete(
  '/:id',
  requirePermission('users.write'),
  asyncHandler(async (req, res) => {
    if (req.params.id === currentUser(req).id) {
      throw ApiError.badRequest('You cannot deactivate your own account');
    }
    await prisma.user.update({ where: { id: req.params.id }, data: { active: false } });
    noContent(res);
  }),
);

export default router;
