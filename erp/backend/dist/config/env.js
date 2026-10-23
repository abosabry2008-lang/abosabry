"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.env = void 0;
const dotenv_1 = __importDefault(require("dotenv"));
dotenv_1.default.config();
function required(name, fallback) {
    const value = process.env[name] ?? fallback;
    if (value === undefined || value === '') {
        throw new Error(`Missing required environment variable "${name}". Copy .env.example to .env and fill it in.`);
    }
    return value;
}
/** Reads an optional variable, treating blank/whitespace as "not set". */
function optional(name) {
    const value = process.env[name]?.trim();
    return value ? value : undefined;
}
const nodeEnv = process.env.NODE_ENV ?? 'development';
exports.env = {
    nodeEnv,
    isProduction: nodeEnv === 'production',
    port: Number(process.env.PORT ?? 4000),
    databaseUrl: required('DATABASE_URL'),
    jwtAccessSecret: required('JWT_ACCESS_SECRET', 'dev-access-secret-change-me'),
    jwtRefreshSecret: required('JWT_REFRESH_SECRET', 'dev-refresh-secret-change-me'),
    accessTokenTtl: process.env.ACCESS_TOKEN_TTL ?? '15m',
    refreshTokenTtl: process.env.REFRESH_TOKEN_TTL ?? '30d',
    // Blank falls back to "*" so a service-to-service reference that resolves to
    // an empty string (e.g. RENDER_EXTERNAL_URL) can never lock out the browser.
    corsOrigin: optional('CORS_ORIGIN') ?? '*',
    bcryptRounds: Number(process.env.BCRYPT_ROUNDS ?? 10),
};
//# sourceMappingURL=env.js.map