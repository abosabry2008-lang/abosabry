import { PrismaClient } from '@prisma/client';
import { env } from '../config/env';

const client = new PrismaClient({
  log: env.isProduction ? ['error'] : ['warn', 'error'],
});

/**
 * Interactive transactions default to a 5 second timeout, which is easily
 * blown when the database lives on a remote server (Neon) and each round trip
 * costs a few hundred milliseconds. Every `$transaction` call gets these
 * friendlier defaults unless the caller passes its own options.
 */
export const TX_OPTIONS = { maxWait: 10_000, timeout: 60_000 } as const;

const originalTransaction = client.$transaction.bind(client) as (
  arg: unknown,
  options?: Record<string, unknown>,
) => Promise<unknown>;
(client as unknown as { $transaction: (arg: unknown, options?: unknown) => Promise<unknown> }).$transaction = (
  arg,
  options,
) =>
  originalTransaction(arg, {
    ...TX_OPTIONS,
    ...((options as Record<string, unknown> | undefined) ?? {}),
  });

export const prisma = client;

export type Db = PrismaClient;
export type Tx = Omit<PrismaClient, '$connect' | '$disconnect' | '$on' | '$transaction' | '$use' | '$extends'>;
