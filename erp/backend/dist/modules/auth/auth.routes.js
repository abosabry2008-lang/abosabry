"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const zod_1 = require("zod");
const env_1 = require("../../config/env");
const api_error_1 = require("../../lib/api-error");
const http_1 = require("../../lib/http");
const password_1 = require("../../lib/password");
const permissions_1 = require("../../lib/permissions");
const prisma_1 = require("../../lib/prisma");
const tokens_1 = require("../../lib/tokens");
const authenticate_1 = require("../../middleware/authenticate");
const validate_1 = require("../../middleware/validate");
const router = (0, express_1.Router)();
const loginSchema = zod_1.z.object({
    email: zod_1.z.string().email(),
    password: zod_1.z.string().min(1),
});
const refreshSchema = zod_1.z.object({
    refreshToken: zod_1.z.string().min(10),
});
const logoutSchema = zod_1.z.object({
    refreshToken: zod_1.z.string().min(10).optional(),
});
function publicUser(user) {
    return {
        id: user.id,
        email: user.email,
        name: user.name,
        role: user.role,
        permissions: (0, permissions_1.permissionsFor)(user.role, user.permissions),
    };
}
async function issueTokens(user) {
    const accessToken = (0, tokens_1.signAccessToken)({ sub: user.id, email: user.email, role: user.role });
    const refreshToken = (0, tokens_1.generateRefreshToken)();
    await prisma_1.prisma.refreshToken.create({
        data: {
            userId: user.id,
            tokenHash: (0, tokens_1.hashToken)(refreshToken),
            expiresAt: new Date(Date.now() + (0, tokens_1.ttlToMs)(env_1.env.refreshTokenTtl)),
        },
    });
    return { accessToken, refreshToken };
}
router.post('/login', (0, validate_1.validateBody)(loginSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const email = String(req.body.email).toLowerCase();
    const user = await prisma_1.prisma.user.findUnique({ where: { email } });
    if (!user || !user.active)
        throw api_error_1.ApiError.unauthorized('Invalid email or password');
    const valid = await (0, password_1.verifyPassword)(String(req.body.password), user.passwordHash);
    if (!valid)
        throw api_error_1.ApiError.unauthorized('Invalid email or password');
    await prisma_1.prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });
    const tokens = await issueTokens(user);
    (0, http_1.ok)(res, { ...tokens, user: publicUser(user) });
}));
router.post('/refresh', (0, validate_1.validateBody)(refreshSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const tokenHash = (0, tokens_1.hashToken)(String(req.body.refreshToken));
    const stored = await prisma_1.prisma.refreshToken.findUnique({
        where: { tokenHash },
        include: { user: true },
    });
    if (!stored || stored.revoked || stored.expiresAt < new Date() || !stored.user.active) {
        throw api_error_1.ApiError.unauthorized('Invalid or expired refresh token');
    }
    // Rotate: revoke the used token and issue a fresh pair.
    await prisma_1.prisma.refreshToken.update({ where: { id: stored.id }, data: { revoked: true } });
    const tokens = await issueTokens(stored.user);
    (0, http_1.ok)(res, tokens);
}));
router.post('/logout', (0, validate_1.validateBody)(logoutSchema), (0, http_1.asyncHandler)(async (req, res) => {
    const token = req.body.refreshToken;
    if (token) {
        await prisma_1.prisma.refreshToken.updateMany({
            where: { tokenHash: (0, tokens_1.hashToken)(token), revoked: false },
            data: { revoked: true },
        });
    }
    (0, http_1.ok)(res, { success: true });
}));
router.get('/me', authenticate_1.authenticate, (0, http_1.asyncHandler)(async (req, res) => {
    const user = await prisma_1.prisma.user.findUnique({ where: { id: (0, authenticate_1.currentUser)(req).id } });
    if (!user || !user.active)
        throw api_error_1.ApiError.unauthorized();
    (0, http_1.ok)(res, publicUser(user));
}));
exports.default = router;
//# sourceMappingURL=auth.routes.js.map