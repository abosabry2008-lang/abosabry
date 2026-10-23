"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ApiError = void 0;
/** An error that is safe to send to API clients. */
class ApiError extends Error {
    constructor(status, message, code = 'ERROR', details) {
        super(message);
        this.name = 'ApiError';
        this.status = status;
        this.code = code;
        this.details = details;
    }
    static badRequest(message, code = 'BAD_REQUEST', details) {
        return new ApiError(400, message, code, details);
    }
    static unauthorized(message = 'Authentication required', code = 'UNAUTHORIZED') {
        return new ApiError(401, message, code);
    }
    static forbidden(message = 'You do not have permission to do that', code = 'FORBIDDEN') {
        return new ApiError(403, message, code);
    }
    static notFound(message = 'Resource not found', code = 'NOT_FOUND') {
        return new ApiError(404, message, code);
    }
    static conflict(message, code = 'CONFLICT', details) {
        return new ApiError(409, message, code, details);
    }
    static unprocessable(message, code = 'UNPROCESSABLE', details) {
        return new ApiError(422, message, code, details);
    }
}
exports.ApiError = ApiError;
//# sourceMappingURL=api-error.js.map