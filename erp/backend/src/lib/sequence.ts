import type { Tx } from './prisma';

/**
 * Allocates the next document number for a named sequence, e.g. SO-2026-00042.
 * The sequence row is locked/incremented inside the caller's transaction.
 */
export async function nextNumber(
  tx: Tx,
  name: string,
  prefix: string,
  now: Date = new Date(),
): Promise<string> {
  const sequence = await tx.sequence.upsert({
    where: { name },
    create: { name, value: 1 },
    update: { value: { increment: 1 } },
  });
  const year = now.getFullYear();
  return `${prefix}-${year}-${String(sequence.value).padStart(5, '0')}`;
}

export async function sequenceValue(tx: Tx, name: string): Promise<number> {
  const sequence = await tx.sequence.findUnique({ where: { name } });
  return sequence?.value ?? 0;
}
