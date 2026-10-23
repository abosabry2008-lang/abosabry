"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const client_1 = require("@prisma/client");
const express_1 = require("express");
const zod_1 = require("zod");
const prisma_1 = require("../../lib/prisma");
const api_error_1 = require("../../lib/api-error");
const http_1 = require("../../lib/http");
const password_1 = require("../../lib/password");
const permissions_1 = require("../../lib/permissions");
const query_1 = require("../../lib/query");
const authenticate_1 = require("../../middleware/authenticate");
const authorize_1 = require("../../middleware/authorize");
const validate_1 = require("../../middleware/validate");
const router = (0, express_1.Router)();
router.use(authenticate_1.authenticate);
const roleEnum = zod_1.z.nativeEnum(client_1.Role);
const createSchema = zod_1.z.object({
    email: zod_1.z.string().email(),
    password: zod_1.z.string().min(8, 'Password must be at least 8 characters'),
    name: zod_1.z.string().min(1),
    role: roleEnum.default('SALES'),
    phone: zod_1.z.string().nullable().optional(),
    active: zod_1.z.boolean().optional(),
    permissions: zod_1.z.array(zod_1.z.string()).nullable().optional(),
});
const updateSchema = zod_1.z.object({
    email: zod_1.z.string().email().optional(),
    password: zod_1.z.string().min(8).optional(),
    name: zod_1.z.string().min(1).optional(),
    role: roleEnum.optional(),
    phone: zod_1.z.string().nullable().optional(),
    active: zod_1.z.boolean().optional(),
    permissions: zod_1.z.array(zod_1.z.string()).nullable().optional(),
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
router.get('/', (0, authorize_1.requirePermission)('users.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const paging = (0, http_1.getPaging)(req.query);
    const search = (0, query_1.asString)(req.query.search);
    const role = (0, query_1.asString)(req.query.role);
    const active = (0, query_1.asBool)(req.query.active);
    const where = {
        ...(search
            ? {
                OR: [
                    { name: { contains: search, mode: 'insensitive' } },
                    { email: { contains: search, mode: 'insensitive' } },
                ],
            }
            : {}),
        ...(role ? { role } : {}),
        ...(active === undefined ? {} : { active }),
    };
    const [total, users] = await Promise.all([
        prisma_1.prisma.user.count({ where }),
        prisma_1.prisma.user.findMany({ where, select, orderBy: { name: 'asc' }, skip: paging.skip, take: paging.take }),
    ]);
    (0, http_1.paginated)(res, users, total, paging);
}));
router.get('/salespersons', (0, authorize_1.requirePermission)('customers.read'), (0, http_1.asyncHandler)(async (_req, res) => {
    const roles = Object.keys(permissions_1.ROLE_PERMISSIONS).filter((role) => (0, permissions_1.roleHasPermission)(role, 'sales.write'));
    const users = await prisma_1.prisma.user.findMany({
        where: { active: true, role: { in: roles } },
        select: { id: true, name: true, email: true, role: true },
        orderBy: { name: 'asc' },
    });
    (0, http_1.ok)(res, users);
}));
router.get('/:id', (0, authorize_1.requirePermission)('users.read'), (0, http_1.asyncHandler)(async (req, res) => {
    const user = await prisma_1.prisma.user.findUnique({ where: { id: req.params.id }, select });
    if (!user)
        throw api_error_1.ApiError.notFound('User not found');
    (0, http_1.ok)(res, user);
}));
router.post('/', (0, authorize_1.requirePermission)('users.write'), (0, validate_1.validateBody)(createSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const user = await prisma_1.prisma.user.create({
        data: {
            email: String(req.body.email).toLowerCase(),
            passwordHash: await (0, password_1.hashPassword)(String(req.body.password)),
            name: req.body.name,
            role: req.body.role,
            phone: req.body.phone ?? null,
            active: req.body.active ?? true,
            ...(req.body.permissions !== undefined ? { permissions: req.body.permissions } : {}),
        },
        select,
    });
    (0, http_1.created)(res, user);
}));
router.patch('/:id', (0, authorize_1.requirePermission)('users.write'), (0, validate_1.validateBody)(updateSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const data = {};
    if (req.body.email !== undefined)
        data.email = String(req.body.email).toLowerCase();
    if (req.body.name !== undefined)
        data.name = req.body.name;
    if (req.body.role !== undefined)
        data.role = req.body.role;
    if (req.body.phone !== undefined)
        data.phone = req.body.phone;
    if (req.body.active !== undefined)
        data.active = req.body.active;
    if (req.body.permissions !== undefined)
        data.permissions = req.body.permissions;
    if (req.body.password)
        data.passwordHash = await (0, password_1.hashPassword)(String(req.body.password));
    const user = await prisma_1.prisma.user.update({ where: { id: req.params.id }, data, select });
    (0, http_1.ok)(res, user);
}));
router.delete('/:id', (0, authorize_1.requirePermission)('users.write'), (0, authorize_1.requireAdmin)(), (0, http_1.asyncHandler)(async (req, res) => {
    if (req.params.id === (0, authenticate_1.currentUser)(req).id) {
        throw api_error_1.ApiError.badRequest('You cannot deactivate your own account');
    }
    await prisma_1.prisma.user.update({ where: { id: req.params.id }, data: { active: false } });
    (0, http_1.noContent)(res);
}));
exports.default = router;
//# sourceMappingURL=users.routes.js.map