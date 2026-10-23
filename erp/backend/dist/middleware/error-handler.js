"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.notFoundHandler = notFoundHandler;
exports.errorHandler = errorHandler;
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const api_error_1 = require("../lib/api-error");
function notFoundHandler(req, _res, next) {
    next(api_error_1.ApiError.notFound(`Route ${req.method} ${req.originalUrl} does not exist`));
}
function toApiError(err) {
    if (err instanceof api_error_1.ApiError)
        return err;
    if (err instanceof zod_1.ZodError) {
        return api_error_1.ApiError.badRequest('Validation failed', 'VALIDATION_ERROR', err.flatten());
    }
    if (err instanceof client_1.Prisma.PrismaClientKnownRequestError) {
        if (err.code === 'P2002') {
            const target = err.meta?.target ?? 'field';
            const fields = Array.isArray(target) ? target.join(', ') : target;
            return api_error_1.ApiError.conflict(`A record with the same ${fields} already exists`, 'DUPLICATE');
        }
        if (err.code === 'P2025') {
            return api_error_1.ApiError.notFound('Record not found');
        }
        if (err.code === 'P2003') {
            return api_error_1.ApiError.badRequest('Related record does not exist (foreign key violation)', 'FOREIGN_KEY');
        }
        return new api_error_1.ApiError(400, `Database error (${err.code})`, 'DB_ERROR');
    }
    if (err instanceof client_1.Prisma.PrismaClientValidationError) {
        return api_error_1.ApiError.badRequest('Invalid data supplied to the database', 'DB_VALIDATION');
    }
    if (err instanceof Error && err.name === 'JsonWebTokenError') {
        return api_error_1.ApiError.unauthorized('Invalid token');
    }
    // body-parser raises a SyntaxError (with a `body` property) for malformed JSON
    // payloads — report it as a client error instead of a 500.
    if (err instanceof SyntaxError && 'body' in err) {
        return api_error_1.ApiError.badRequest('Request body is not valid JSON', 'INVALID_JSON');
    }
    return new api_error_1.ApiError(500, 'Internal server error', 'INTERNAL');
}
// eslint-disable-next-line @typescript-eslint/no-unused-vars
function errorHandler(err, _req, res, _next) {
    const apiError = toApiError(err);
    // Always log server-side errors (Vercel collects stdout/stderr per request),
    // so 500s are diagnosable in production too.
    if (apiError.status >= 500) {
        // eslint-disable-next-line no-console
        console.error('[error]', err);
    }
    const body = {
        error: {
            message: apiError.message,
            code: apiError.code,
        },
    };
    if (apiError.details !== undefined)
        body.error.details = apiError.details;
    res.status(apiError.status).json(body);
}
//# sourceMappingURL=error-handler.js.map