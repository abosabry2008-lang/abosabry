#!/usr/bin/env node
/**
 * Vercel build command (runs on Vercel's Linux builder; also works on Windows).
 *
 *   1. npm ci --include=dev   in erp/backend (TypeScript + Prisma CLI)
 *   2. npx prisma generate
 *   3. npx tsc               → erp/backend/dist
 *   4. copy erp/web → public/  (Vercel's static directory)
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
run('npx', ['tsc', '-p', 'tsconfig.json']);

if (!fs.existsSync(path.join(web, 'index.html'))) {
  throw new Error(`Missing ${web}/index.html — build the Flutter web app first (erp/deploy/build_web.ps1).`);
}

fs.rmSync(out, { recursive: true, force: true });
fs.cpSync(web, out, { recursive: true });

// eslint-disable-next-line no-console
console.log(`[vercel] build OK → ${out}`);
