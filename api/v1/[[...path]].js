/**
 * Vercel entry point — the whole Express API (mounted at /api/v1) runs as one
 * serverless function. Requests under /api/v1 reach this file with their
 * original path, so every route in erp/backend/src/routes works unchanged.
 *
 * ⚠️ Fallback only: Vercel's filesystem router matches a SINGLE path segment
 * for this file (`/api/v1/health` ✔, `/api/v1/auth/login` ✘). Multi-segment
 * routes are handled by the rewrite in vercel.json → `api/index.js`, which
 * receives every `/api/**` request. Keep this file so shallow routes still
 * work if that rewrite is ever removed.
 */
const { createApp } = require('../../erp/backend/dist/app');

module.exports = createApp();
