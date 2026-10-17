import crypto from 'crypto';
import jwt, { type SignOptions } from 'jsonwebtoken';
import { env } from '../config/env';

export interface AccessPayload {
  sub: string;
  email: string;
  role: string;
}

const accessTtl = env.accessTokenTtl as unknown as SignOptions['expiresIn'];

export function signAccessToken(payload: AccessPayload): string {
  return jwt.sign(payload, env.jwtAccessSecret, { expiresIn: accessTtl });
}

export function verifyAccessToken(token: string): AccessPayload {
  return jwt.verify(token, env.jwtAccessSecret) as AccessPayload;
}

/** Refresh tokens are opaque random strings; only their hash is stored. */
export function generateRefreshToken(): string {
  return crypto.randomBytes(48).toString('hex');
}

export function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/** Converts "30d" / "12h" / "15m" / "3600" into milliseconds. */
export function ttlToMs(ttl: string, fallbackMs = 30 * 24 * 60 * 60 * 1000): number {
  const match = /^(\d+)\s*([smhd])?$/.exec(ttl.trim());
  if (!match) return fallbackMs;
  const amount = Number(match[1]);
  const unit = match[2] ?? 's';
  const factor: Record<string, number> = { s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 };
  return amount * (factor[unit] ?? 1000);
}
