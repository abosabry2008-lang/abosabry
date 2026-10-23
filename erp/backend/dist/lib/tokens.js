"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.signAccessToken = signAccessToken;
exports.verifyAccessToken = verifyAccessToken;
exports.generateRefreshToken = generateRefreshToken;
exports.hashToken = hashToken;
exports.ttlToMs = ttlToMs;
const crypto_1 = __importDefault(require("crypto"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const env_1 = require("../config/env");
const accessTtl = env_1.env.accessTokenTtl;
function signAccessToken(payload) {
    return jsonwebtoken_1.default.sign(payload, env_1.env.jwtAccessSecret, { expiresIn: accessTtl });
}
function verifyAccessToken(token) {
    return jsonwebtoken_1.default.verify(token, env_1.env.jwtAccessSecret);
}
/** Refresh tokens are opaque random strings; only their hash is stored. */
function generateRefreshToken() {
    return crypto_1.default.randomBytes(48).toString('hex');
}
function hashToken(token) {
    return crypto_1.default.createHash('sha256').update(token).digest('hex');
}
/** Converts "30d" / "12h" / "15m" / "3600" into milliseconds. */
function ttlToMs(ttl, fallbackMs = 30 * 24 * 60 * 60 * 1000) {
    const match = /^(\d+)\s*([smhd])?$/.exec(ttl.trim());
    if (!match)
        return fallbackMs;
    const amount = Number(match[1]);
    const unit = match[2] ?? 's';
    const factor = { s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 };
    return amount * (factor[unit] ?? 1000);
}
//# sourceMappingURL=tokens.js.map