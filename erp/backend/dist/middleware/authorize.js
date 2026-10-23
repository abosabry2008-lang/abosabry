"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requirePermission = requirePermission;
exports.requireAdmin = requireAdmin;
const api_error_1 = require("../lib/api-error");
const permissions_1 = require("../lib/permissions");
/** Requires the authenticated user's role to grant the given permission. */
function requirePermission(permission) {
    return (req, _res, next) => {
        if (!req.user)
            throw api_error_1.ApiError.unauthorized();
        if (!(0, permissions_1.roleHasPermission)(req.user.role, permission)) {
            throw api_error_1.ApiError.forbidden(`Your role (${req.user.role}) lacks the "${permission}" permission`);
        }
        next();
    };
}
/**
 * Requires the ADMIN role. Used for destructive operations (delete / cancel /
 * void) that must never be delegable through the role-permission editor.
 */
function requireAdmin() {
    return (req, _res, next) => {
        if (!req.user)
            throw api_error_1.ApiError.unauthorized();
        if ((req.user.role ?? '').toUpperCase() !== 'ADMIN') {
            throw api_error_1.ApiError.forbidden('Only an administrator can perform this action');
        }
        next();
    };
}
//# sourceMappingURL=authorize.js.map