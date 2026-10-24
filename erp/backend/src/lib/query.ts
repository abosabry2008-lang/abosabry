/** Small helpers for reading untyped Express query values. */

import { tzOffsetMinutes } from './local-time';

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Local midnight for a `YYYY-MM-DD` calendar date. */
function localStartOfDay(text: string): Date {
  const [year, month, day] = text.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day) - tzOffsetMinutes() * 60_000);
}

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
  // A date-only value is a calendar day chosen in the browser, so it must be
  // anchored to local midnight rather than UTC midnight.
  const date = DATE_ONLY.test(text) ? localStartOfDay(text) : new Date(text);
  return Number.isNaN(date.getTime()) ? undefined : date;
};

/** Like [asDate], but a date-only value means the end of that local day. */
export const asDateEnd = (value: unknown): Date | undefined => {
  const text = asString(value);
  if (text === undefined) return undefined;
  if (DATE_ONLY.test(text)) {
    return new Date(localStartOfDay(text).getTime() + DAY_MS - 1);
  }
  return asDate(text);
};

export const asEnum = <T extends string>(value: unknown, allowed: readonly T[]): T | undefined => {
  const text = asString(value);
  if (text === undefined) return undefined;
  const upper = text.toUpperCase() as T;
  return allowed.includes(upper) ? upper : undefined;
};
