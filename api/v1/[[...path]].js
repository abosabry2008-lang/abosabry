/**
 * Vercel entry point — the whole Express API (mounted at /api/v1) runs as one
 * serverless function. Requests under /api/v1 reach this file with their
 * original path, so every route in erp/backend/src/routes works unchanged.
 *
 * Everything else (the Flutter web bundle) is served statically by Vercel from
 * `public/` (copied from erp/web by erp/deploy/vercel/build.mjs), and unknown
 * paths fall back to index.html via vercel.json — the SPA behaviour of
 * erp/backend/src/app.ts, reproduced outside the container.
 */
const { createApp } = require('../../erp/backend/dist/app');

module.exports = createApp();
