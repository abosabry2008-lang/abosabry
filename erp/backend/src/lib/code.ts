/**
 * Human-friendly codes for customers / suppliers (كود العميل / كود المورد).
 *
 * The shop may type its own code; when it leaves the field blank a sequential
 * one is generated (`CUS-0001`, `SUP-0001`, ...) so every record always has a
 * unique, printable code.
 */

/** Returns true when the caller really typed something. */
export const hasCode = (value: unknown): boolean =>
  typeof value === 'string' && value.trim().length > 0;

/**
 * Builds the next code for a prefix, skipping any value already in `taken`.
 * `existing` is the full set of used codes (case-insensitive).
 */
export function nextCode(prefix: string, existing: Set<string>, width = 4): string {
  const used = new Set(Array.from(existing, (code) => code.toUpperCase()));
  let n = 1;
  for (;;) {
    const candidate = `${prefix}-${String(n).padStart(width, '0')}`;
    if (!used.has(candidate.toUpperCase())) return candidate;
    n += 1;
  }
}

/** Uppercase, trimmed code with a safe fallback when empty. */
export function normalizeCode(value: unknown, fallbackPrefix: string, existing: Set<string>): string {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (trimmed.length === 0) return nextCode(fallbackPrefix, existing);
  return trimmed;
}
