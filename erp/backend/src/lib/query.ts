/** Small helpers for reading untyped Express query values. */

export const asString = (value: unknown): string | undefined => {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : undefined;
  }
  if (typeof value === 'number') return String(value);
  return undefined;
};

export const asBool = (value: unknown): boolean | undefined => {
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value === 'boolean') return value;
  const text = String(value).toLowerCase();
  if (['true', '1', 'yes', 'y'].includes(text)) return true;
  if (['false', '0', 'no', 'n'].includes(text)) return false;
  return undefined;
};

export const asNumber = (value: unknown): number | undefined => {
  const text = asString(value);
  if (text === undefined) return undefined;
  const parsed = Number(text);
  return Number.isFinite(parsed) ? parsed : undefined;
};

export const asDate = (value: unknown): Date | undefined => {
  const text = asString(value);
  if (text === undefined) return undefined;
  const date = new Date(text);
  return Number.isNaN(date.getTime()) ? undefined : date;
};

export const asEnum = <T extends string>(value: unknown, allowed: readonly T[]): T | undefined => {
  const text = asString(value);
  if (text === undefined) return undefined;
  const upper = text.toUpperCase() as T;
  return allowed.includes(upper) ? upper : undefined;
};
