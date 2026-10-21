import { Router } from 'express';
import { Role } from '@prisma/client';
import { z } from 'zod';
import { env } from '../../config/env';
import { ApiError } from '../../lib/api-error';
import { asyncHandler, ok } from '../../lib/http';
import { verifyPassword } from '../../lib/password';
import { permissionsFor } from '../../lib/permissions';
import { prisma } from '../../lib/prisma';
import { generateRefreshToken, hashToken, signAccessToken, ttlToMs } from '../../lib/tokens';
import { authenticate, currentUser } from '../../middleware/authenticate';
import { validateBody } from '../../middleware/validate';

const router = Router();

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(10),
});

const logoutSchema = z.object({
  refreshToken: z.string().min(10).optional(),
});

interface SessionUser {
  id: string;
  email: string;
  name: string;
  role: Role;
  permissions?: unknown;
}

function publicUser(user: SessionUser & { permissions?: unknown }) {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    role: user.role,
    permissions: permissionsFor(user.role, (user as any).permissions),
  };
}

async function issueTokens(user: SessionUser) {
  const accessToken = signAccessToken({ sub: user.id, email: user.email, role: user.role });
  const refreshToken = generateRefreshToken();
  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      tokenHash: hashToken(refreshToken),
      expiresAt: new Date(Date.now() + ttlToMs(env.refreshTokenTtl)),
    },
  });
  return { accessToken, refreshToken };
}

router.post(
  '/login',
  validateBody(loginSchema),
  asyncHandler(async (req, res) => {
    const email = String(req.body.email).toLowerCase();
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user || !user.active) throw ApiError.unauthorized('Invalid email or password');

    const valid = await verifyPassword(String(req.body.password), user.passwordHash);
    if (!valid) throw ApiError.unauthorized('Invalid email or password');

    await prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });

    const tokens = await issueTokens(user);
    ok(res, { ...tokens, user: publicUser(user) });
  }),
);

router.post(
  '/refresh',
  validateBody(refreshSchema),
  asyncHandler(async (req, res) => {
    const tokenHash = hashToken(String(req.body.refreshToken));
    const stored = await prisma.refreshToken.findUnique({
      where: { tokenHash },
      include: { user: true },
    });

    if (!stored || stored.revoked || stored.expiresAt < new Date() || !stored.user.active) {
      throw ApiError.unauthorized('Invalid or expired refresh token');
    }

    // Rotate: revoke the used token and issue a fresh pair.
    await prisma.refreshToken.update({ where: { id: stored.id }, data: { revoked: true } });
    const tokens = await issueTokens(stored.user);
    ok(res, tokens);
  }),
);

router.post(
  '/logout',
  validateBody(logoutSchema),
  asyncHandler(async (req, res) => {
    const token = req.body.refreshToken as string | undefined;
    if (token) {
      await prisma.refreshToken.updateMany({
        where: { tokenHash: hashToken(token), revoked: false },
        data: { revoked: true },
      });
    }
    ok(res, { success: true });
  }),
);

router.get(
  '/me',
  authenticate,
  asyncHandler(async (req, res) => {
    const user = await prisma.user.findUnique({ where: { id: currentUser(req).id } });
    if (!user || !user.active) throw ApiError.unauthorized();
    ok(res, publicUser(user));
  }),
);

export default router;
