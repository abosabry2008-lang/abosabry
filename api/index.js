/**
 * Vercel entry point — the whole Express API runs as one serverless function.
 *
 * `vercel.json` rewrites every `/api/**` request to this file (see below), so
 * the app receives the original path (`/api/v1/...`) and all routes in
 * erp/backend/src/routes work unchanged.
 *
 * NOTE: a catch-all file (`api/v1/[[...path]].js`) alone is NOT enough —
 * Vercel's filesystem router only matches a single path segment for it, so
 * nested routes like `/api/v1/auth/login` returned a platform 404
 * (`x-vercel-error: NOT_FOUND`). The rewrite in vercel.json is what makes
 * multi-segment routes reach this function.
 */
const { createApp } = require('../erp/backend/dist/app');

module.exports = createApp();
