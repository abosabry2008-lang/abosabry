import type { RequestHandler } from 'express';
import type { ZodTypeAny } from 'zod';
import { ApiError } from '../lib/api-error';

export const validateBody =
  (schema: ZodTypeAny): RequestHandler =>
  (req, _res, next) => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      throw ApiError.badRequest('Validation failed', 'VALIDATION_ERROR', result.error.flatten());
    }
    req.body = result.data;
    next();
  };

export const validateQuery =
  (schema: ZodTypeAny): RequestHandler =>
  (req, _res, next) => {
    const result = schema.safeParse(req.query);
    if (!result.success) {
      throw ApiError.badRequest('Invalid query parameters', 'VALIDATION_ERROR', result.error.flatten());
    }
    next();
  };
