import type { NextFunction, Request, RequestHandler, Response } from 'express';
import { Role } from '@prisma/client';
import { ApiError } from '../lib/api-error';
import { verifyAccessToken } from '../lib/tokens';

/**
 * Like `authenticate`, but also accepts the access token from a `token` query
 * parameter. Print pages are opened directly in a browser (where setting an
 * Authorization header is not possible), so the Flutter client appends
 * `?token=<access token>` to the print URL.
 *
 * The token is read from the `Authorization: Bearer` header first, then from
 * `req.query.token`. `req.user` is attached with the same shape as the regular
 * `authenticate` middleware.
 */
export const authenticateToken: RequestHandler = (req: Request, _res: Response, next: NextFunction) => {
  let token: string | undefined;

  const header = req.headers.authorization;
  if (header && header.startsWith('Bearer ')) {
    const value = header.slice('Bearer '.length).trim();
    if (value.length > 0) token = value;
  }

  if (!token) {
    const queryToken = req.query.token;
    if (typeof queryToken === 'string' && queryToken.trim().length > 0) {
      token = queryToken.trim();
    }
  }

  if (!token) {
    throw ApiError.unauthorized('Missing access token');
  }

  try {
    const payload = verifyAccessToken(token);
    req.user = { id: payload.sub, email: payload.email, role: payload.role as Role };
    next();
  } catch {
    throw ApiError.unauthorized('Invalid or expired access token');
  }
};
