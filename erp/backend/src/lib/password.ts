import bcrypt from 'bcryptjs';
import { env } from '../config/env';

export const hashPassword = (plain: string): Promise<string> =>
  bcrypt.hash(plain, env.bcryptRounds);

export const verifyPassword = (plain: string, hash: string): Promise<boolean> =>
  bcrypt.compare(plain, hash);
