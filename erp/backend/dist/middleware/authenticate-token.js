"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.authenticateToken = void 0;
const api_error_1 = require("../lib/api-error");
const tokens_1 = require("../lib/tokens");
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
const authenticateToken = (req, _res, next) => {
    let token;
    const header = req.headers.authorization;
    if (header && header.startsWith('Bearer ')) {
        const value = header.slice('Bearer '.length).trim();
        if (value.length > 0)
            token = value;
    }
    if (!token) {
        const queryToken = req.query.token;
        if (typeof queryToken === 'string' && queryToken.trim().length > 0) {
            token = queryToken.trim();
        }
    }
    if (!token) {
        throw api_error_1.ApiError.unauthorized('Missing access token');
    }
    try {
        const payload = (0, tokens_1.verifyAccessToken)(token);
        req.user = { id: payload.sub, email: payload.email, role: payload.role };
        next();
    }
    catch {
        throw api_error_1.ApiError.unauthorized('Invalid or expired access token');
    }
};
exports.authenticateToken = authenticateToken;
//# sourceMappingURL=authenticate-token.js.map