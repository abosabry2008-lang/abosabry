import type { RequestHandler } from 'express';
import { ApiError } from '../lib/api-error';
import { roleHasPermission, type Permission } from '../lib/permissions';

/** Requires the authenticated user's role to grant the given permission. */
export function requirePermission(permission: Permission): RequestHandler {
  return (req, _res, next) => {
    if (!req.user) throw ApiError.unauthorized();
    if (!roleHasPermission(req.user.role, permission)) {
      throw ApiError.forbidden(`Your role (${req.user.role}) lacks the "${permission}" permission`);
    }
    next();
  };
}

/**
 * Requires the ADMIN role. Used for destructive operations (delete / cancel /
 * void) that must never be delegable through the role-permission editor.
 */
export function requireAdmin(): RequestHandler {
  return (req, _res, next) => {
    if (!req.user) throw ApiError.unauthorized();
    if ((req.user.role ?? '').toUpperCase() !== 'ADMIN') {
      throw ApiError.forbidden('Only an administrator can perform this action');
    }
    next();
  };
}
