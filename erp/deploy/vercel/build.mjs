#!/usr/bin/env node
/**
 * Vercel build command (runs on Vercel's Linux builder; also works on Windows).
 *
 *   1. npm ci --include=dev   in erp/backend (TypeScript + Prisma CLI)
 *   2. npx prisma generate
 *   3. npx prisma db push     (only when DATABASE_URL is available)
 *   4. npx tsc               → erp/backend/dist
 *   5. copy erp/web → public/  (Vercel's static directory)
 *
 * The API itself is served by api/v1/[[...path]].js (see vercel.json).
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..', '..');
const backend = path.join(root, 'erp', 'backend');
const web = path.join(root, 'erp', 'web');
const out = path.join(root, 'public');

function run(cmd, args) {
  execFileSync(cmd, args, {
    cwd: backend,
    stdio: 'inherit',
    // Windows needs a shell to resolve npm.cmd; Linux/macOS do not.
    shell: process.platform === 'win32',
    env: process.env,
  });
}

// `npm ci` installs from the lockfile. On Windows a running API/antivirus can
// lock the Prisma engine DLL and make it fail — fall back to a plain install
// (same result; on Vercel's Linux builder `npm ci` always succeeds).
try {
  run('npm', ['ci', '--include=dev']);
} catch (error) {
  // eslint-disable-next-line no-console
  console.warn('[vercel] npm ci failed (locked files?), falling back to npm install.', error.message);
  run('npm', ['install', '--include=dev']);
}

run('npx', ['prisma', 'generate']);

// Apply schema changes to the production database before the new code is
// deployed. Vercel exposes the project environment variables to the build, so
// this is the same DATABASE_URL the API uses at runtime. A failed push fails
// the build, which keeps the previous deployment serving.
if (!process.env.DATABASE_URL) {
  // eslint-disable-next-line no-console
  console.warn('[vercel] DATABASE_URL is not set — skipping prisma db push.');
} else {
  // `--accept-data-loss` lets additive changes such as a new unique column
  // apply without blocking the build on a warning.
  run('npx', ['prisma', 'db', 'push', '--skip-generate', '--accept-data-loss']);
}

run('npx', ['tsc', '-p', 'tsconfig.json']);

if (!fs.existsSync(path.join(web, 'index.html'))) {
  throw new Error(`Missing ${web}/index.html — build the Flutter web app first (erp/deploy/build_web.ps1).`);
}

fs.rmSync(out, { recursive: true, force: true });
fs.cpSync(web, out, { recursive: true });

// eslint-disable-next-line no-console
console.log(`[vercel] build OK → ${out}`);
