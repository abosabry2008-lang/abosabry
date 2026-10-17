import type { NextFunction, Request, Response } from 'express';
import { Prisma } from '@prisma/client';
import { ZodError } from 'zod';
import { env } from '../config/env';
import { ApiError } from '../lib/api-error';

export function notFoundHandler(req: Request, _res: Response, next: NextFunction): void {
  next(ApiError.notFound(`Route ${req.method} ${req.originalUrl} does not exist`));
}

interface ErrorBody {
  error: {
    message: string;
    code: string;
    details?: unknown;
  };
}

function toApiError(err: unknown): ApiError {
  if (err instanceof ApiError) return err;

  if (err instanceof ZodError) {
    return ApiError.badRequest('Validation failed', 'VALIDATION_ERROR', err.flatten());
  }

  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    if (err.code === 'P2002') {
      const target = (err.meta?.target as string[] | string | undefined) ?? 'field';
      const fields = Array.isArray(target) ? target.join(', ') : target;
      return ApiError.conflict(`A record with the same ${fields} already exists`, 'DUPLICATE');
    }
    if (err.code === 'P2025') {
      return ApiError.notFound('Record not found');
    }
    if (err.code === 'P2003') {
      return ApiError.badRequest('Related record does not exist (foreign key violation)', 'FOREIGN_KEY');
    }
    return new ApiError(400, `Database error (${err.code})`, 'DB_ERROR');
  }

  if (err instanceof Prisma.PrismaClientValidationError) {
    return ApiError.badRequest('Invalid data supplied to the database', 'DB_VALIDATION');
  }

  if (err instanceof Error && err.name === 'JsonWebTokenError') {
    return ApiError.unauthorized('Invalid token');
  }

  return new ApiError(500, 'Internal server error', 'INTERNAL');
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction): void {
  const apiError = toApiError(err);

  if (!env.isProduction && apiError.status >= 500) {
    // eslint-disable-next-line no-console
    console.error('[error]', err);
  }

  const body: ErrorBody = {
    error: {
      message: apiError.message,
      code: apiError.code,
    },
  };
  if (apiError.details !== undefined) body.error.details = apiError.details;

  res.status(apiError.status).json(body);
}
