import { createApp } from './app';
import { env } from './config/env';
import { prisma } from './lib/prisma';

async function main(): Promise<void> {
  try {
    await prisma.$connect();
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error(
      '\nCould not connect to PostgreSQL.\n' +
        '  1. Is a database running? Try:  docker compose up -d\n' +
        '  2. Have you applied the schema?  npx prisma migrate deploy  (or  npx prisma db push)\n' +
        '  3. Check DATABASE_URL in your .env file.\n',
    );
    throw error;
  }

  const app = createApp();
  const server = app.listen(env.port, () => {
    // eslint-disable-next-line no-console
    console.log(`ERP API ready on http://localhost:${env.port}/api/v1  (${env.nodeEnv})`);
  });

  const shutdown = async (signal: string): Promise<void> => {
    // eslint-disable-next-line no-console
    console.log(`\n${signal} received - shutting down.`);
    server.close();
    await prisma.$disconnect();
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
