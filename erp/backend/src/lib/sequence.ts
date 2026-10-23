import { ApiError } from './api-error';
import type { Tx } from './prisma';

/**
 * Checks whether a generated document number is already used by the target table.
 * Callers pass a cheap `count`/`findUnique` lookup for their own model.
 */
export type NumberTaken = (candidate: string) => Promise<boolean>;

/**
 * Allocates the next document number for a named sequence, e.g. SO-2026-00042.
 * The sequence row is locked/incremented inside the caller's transaction.
 *
 * A sequence can drift behind the rows that already exist (records imported or
 * seeded before the sequence was created, a rollback that never advanced it,
 * etc.). When `isTaken` is supplied we walk forward until a free number is
 * found instead of failing with a unique-constraint error on every save.
 */
export async function nextNumber(
  tx: Tx,
  name: string,
  prefix: string,
  now: Date = new Date(),
  isTaken?: NumberTaken,
): Promise<string> {
  const year = now.getFullYear();
  for (let attempt = 0; attempt < 2000; attempt += 1) {
    const sequence = await tx.sequence.upsert({
      where: { name },
      create: { name, value: 1 },
      update: { value: { increment: 1 } },
    });
    const candidate = `${prefix}-${year}-${String(sequence.value).padStart(5, '0')}`;
    if (!isTaken || !(await isTaken(candidate))) return candidate;
  }
  throw ApiError.conflict(
    `Unable to allocate a unique ${name} number`,
    'NUMBER_ALLOCATION_FAILED',
  );
}

/**
 * Reserves `count` consecutive numbers in one sequence update. This is used by
 * bulk documents (e.g. a collection receipt with 50 customer lines) so the
 * database is not hit once per line.
 *
 * When `areTaken`/`isTaken` detect a drift, the colliding numbers are skipped by
 * falling back to [nextNumber] for that slot.
 */
export async function nextNumbers(
  tx: Tx,
  name: string,
  prefix: string,
  count: number,
  now: Date = new Date(),
  areTaken?: (candidates: string[]) => Promise<Set<string>>,
  isTaken?: NumberTaken,
): Promise<string[]> {
  if (count <= 0) return [];

  const year = now.getFullYear();
  const sequence = await tx.sequence.upsert({
    where: { name },
    create: { name, value: count },
    update: { value: { increment: count } },
  });
  const start = sequence.value - count + 1;
  const candidates = Array.from(
    { length: count },
    (_, index) => `${prefix}-${year}-${String(start + index).padStart(5, '0')}`,
  );

  if (!areTaken) return candidates;

  const taken = await areTaken(candidates);
  if (taken.size === 0) return candidates;

  const resolved: string[] = [];
  for (const candidate of candidates) {
    resolved.push(
      taken.has(candidate)
        ? await nextNumber(tx, name, prefix, now, isTaken)
        : candidate,
    );
  }
  return resolved;
}

export async function sequenceValue(tx: Tx, name: string): Promise<number> {
  const sequence = await tx.sequence.findUnique({ where: { name } });
  return sequence?.value ?? 0;
}
