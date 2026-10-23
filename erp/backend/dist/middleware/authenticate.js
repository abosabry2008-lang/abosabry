"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.authenticate = authenticate;
exports.currentUser = currentUser;
const api_error_1 = require("../lib/api-error");
const settings_1 = require("../lib/settings");
const tokens_1 = require("../lib/tokens");
/**
 * Verifies the Bearer access token and attaches req.user.
 *
 * This is async (it may load role-permission overrides from the database), so
 * errors must be forwarded with `next(err)` — Express 4 does not catch
 * rejections from async middleware on its own.
 */
async function authenticate(req, _res, next) {
    try {
        const header = req.headers.authorization;
        if (!header || !header.startsWith('Bearer ')) {
            throw api_error_1.ApiError.unauthorized('Missing bearer token');
        }
        const token = header.slice('Bearer '.length).trim();
        let payload;
        try {
            payload = (0, tokens_1.verifyAccessToken)(token);
        }
        catch {
            throw api_error_1.ApiError.unauthorized('Invalid or expired access token');
        }
        req.user = { id: payload.sub, email: payload.email, role: payload.role };
        // Make sure role-permission overrides from settings are in memory.
        await (0, settings_1.ensureRolePermissionsLoaded)();
        next();
    }
    catch (error) {
        next(error);
    }
}
function currentUser(req) {
    if (!req.user)
        throw api_error_1.ApiError.unauthorized();
    return req.user;
}
//# sourceMappingURL=authenticate.js.map