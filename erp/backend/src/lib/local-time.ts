import { AsyncLocalStorage } from 'node:async_hooks';

/**
 * Per-request timezone offset (minutes east of UTC).
 *
 * Documents and reports must show the user's calendar day, not the server's.
 * The browser sends its offset with every request; storing it in async-local
 * storage lets the date helpers below stay simple and synchronous.
 */
interface TimezoneContext {
  offsetMinutes: number;
}

const storage = new AsyncLocalStorage<TimezoneContext>();

/** Runs [fn] with the supplied browser timezone offset. */
export function runWithTzOffset<T>(offsetMinutes: number, fn: () => T): T {
  const safe = Number.isFinite(offsetMinutes) ? offsetMinutes : 0;
  return storage.run({ offsetMinutes: safe }, fn);
}

/** Current offset in minutes; defaults to UTC when the request has none. */
export function tzOffsetMinutes(): number {
  return storage.getStore()?.offsetMinutes ?? 0;
}

/** Shifts an instant so its UTC getters read as local wall-clock values. */
function shifted(date: Date): Date {
  return new Date(date.getTime() + tzOffsetMinutes() * 60_000);
}

const pad = (value: number): string => String(value).padStart(2, '0');

/** `YYYY-MM-DD` for the user's local calendar day. */
export function localDayKey(date: Date): string {
  const d = shifted(date);
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

/** `YYYY-MM` for the user's local calendar month. */
export function localMonthKey(date: Date): string {
  const d = shifted(date);
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}`;
}

/** `YYYY-MM-DD HH:mm` in the user's local time. */
export function localStamp(date: Date): string {
  const d = shifted(date);
  return `${localDayKey(date)} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
}
