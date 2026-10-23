"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.validateQuery = exports.validateBody = void 0;
const api_error_1 = require("../lib/api-error");
const validateBody = (schema) => (req, _res, next) => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
        throw api_error_1.ApiError.badRequest('Validation failed', 'VALIDATION_ERROR', result.error.flatten());
    }
    req.body = result.data;
    next();
};
exports.validateBody = validateBody;
const validateQuery = (schema) => (req, _res, next) => {
    const result = schema.safeParse(req.query);
    if (!result.success) {
        throw api_error_1.ApiError.badRequest('Invalid query parameters', 'VALIDATION_ERROR', result.error.flatten());
    }
    next();
};
exports.validateQuery = validateQuery;
//# sourceMappingURL=validate.js.map