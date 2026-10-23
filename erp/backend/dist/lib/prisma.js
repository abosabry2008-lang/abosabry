"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.prisma = exports.TX_OPTIONS = void 0;
const client_1 = require("@prisma/client");
const env_1 = require("../config/env");
const client = new client_1.PrismaClient({
    log: env_1.env.isProduction ? ['error'] : ['warn', 'error'],
});
/**
 * Interactive transactions default to a 5 second timeout, which is easily
 * blown when the database lives on a remote server (Neon) and each round trip
 * costs a few hundred milliseconds. Every `$transaction` call gets these
 * friendlier defaults unless the caller passes its own options.
 */
exports.TX_OPTIONS = { maxWait: 10_000, timeout: 60_000 };
const originalTransaction = client.$transaction.bind(client);
client.$transaction = (arg, options) => originalTransaction(arg, {
    ...exports.TX_OPTIONS,
    ...(options ?? {}),
});
exports.prisma = client;
//# sourceMappingURL=prisma.js.map