"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const app_1 = require("./app");
const env_1 = require("./config/env");
const prisma_1 = require("./lib/prisma");
async function main() {
    try {
        await prisma_1.prisma.$connect();
    }
    catch (error) {
        // eslint-disable-next-line no-console
        console.error('\nCould not connect to PostgreSQL.\n' +
            '  1. Is a database running? Try:  docker compose up -d\n' +
            '  2. Have you applied the schema?  npx prisma migrate deploy  (or  npx prisma db push)\n' +
            '  3. Check DATABASE_URL in your .env file.\n');
        throw error;
    }
    const app = (0, app_1.createApp)();
    const server = app.listen(env_1.env.port, () => {
        // eslint-disable-next-line no-console
        console.log(`ERP API ready on http://localhost:${env_1.env.port}/api/v1  (${env_1.env.nodeEnv})`);
    });
    const shutdown = async (signal) => {
        // eslint-disable-next-line no-console
        console.log(`\n${signal} received - shutting down.`);
        server.close();
        await prisma_1.prisma.$disconnect();
        process.exit(0);
    };
    process.on('SIGINT', () => void shutdown('SIGINT'));
    process.on('SIGTERM', () => void shutdown('SIGTERM'));
}
main().catch((error) => {
    // eslint-disable-next-line no-console
    console.error(error);
    process.exit(1);
});
//# sourceMappingURL=server.js.map