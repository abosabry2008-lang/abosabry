import type { NextFunction, Request, RequestHandler, Response } from 'express';
import { Role } from '@prisma/client';
import { ApiError } from '../lib/api-error';
import { parseCustomPermissions } from '../lib/permissions';
import { prisma } from '../lib/prisma';
import { ensureRolePermissionsLoaded } from '../lib/settings';
import { verifyAccessToken } from '../lib/tokens';

export interface AuthUser {
  id: string;
  email: string;
  role: Role;
  /** Per-user overrides; when present they replace the role defaults. */
  permissions?: string[];
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

/**
 * Verifies the Bearer access token and attaches req.user.
 *
 * This is async (it may load role-permission overrides from the database), so
 * errors must be forwarded with `next(err)` — Express 4 does not catch
 * rejections from async middleware on its own.
 */
export async function authenticate(
  req: Request,
  _res: Response,
  next: NextFunction,
): Promise<void> {
  try {
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      throw ApiError.unauthorized('Missing bearer token');
    }
    const token = header.slice('Bearer '.length).trim();
    let payload;
    try {
      payload = verifyAccessToken(token);
    } catch {
      throw ApiError.unauthorized('Invalid or expired access token');
    }
    const account = await prisma.user.findUnique({
      where: { id: payload.sub },
      select: { role: true, active: true, permissions: true },
    });
    if (!account || !account.active) {
      throw ApiError.unauthorized('This account is inactive or no longer exists');
    }
    req.user = {
      id: payload.sub,
      email: payload.email,
      role: account.role,
      permissions: Array.isArray(payload.permissions)
        ? payload.permissions
        : parseCustomPermissions(account.permissions),
    };
    // Make sure role-permission overrides from settings are in memory.
    await ensureRolePermissionsLoaded();
    next();
  } catch (error) {
    next(error);
  }
}

export function currentUser(req: Request): AuthUser {
  if (!req.user) throw ApiError.unauthorized();
  return req.user;
}
