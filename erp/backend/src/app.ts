import cors from 'cors';
import express, { type Express } from 'express';
import fs from 'fs';
import helmet from 'helmet';
import morgan from 'morgan';
import path from 'path';
import { env } from './config/env';
import { errorHandler, notFoundHandler } from './middleware/error-handler';
import api from './routes';

/**
 * Finds the compiled Flutter web app, which is served from the same origin as
 * the API when it is present (one URL, no CORS, works on any container host).
 *
 * Looks at `WEB_ROOT` first, then the two layouts we ship in:
 *   - `/app/web`  (Docker image built from the repo root Dockerfile)
 *   - `erp/web`   (running straight from the repository)
 */
function findWebRoot(): string | null {
  const candidates = [
    process.env.WEB_ROOT,
    path.resolve(__dirname, '../web'),
    path.resolve(__dirname, '../../web'),
  ].filter((value): value is string => Boolean(value && value.trim()));

  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, 'index.html'))) {
      return candidate;
    }
  }
  return null;
}

export function createApp(): Express {
  const app = express();
  const webRoot = findWebRoot();

  app.disable('x-powered-by');
  // CSP is disabled on purpose: the Flutter/CanvasKit bundle instantiates
  // WebAssembly, which needs `wasm-unsafe-eval`. Only our own assets are served.
  app.use(helmet({ contentSecurityPolicy: false }));
  app.use(
    cors({
      origin: env.corsOrigin === '*' ? true : env.corsOrigin.split(',').map((value) => value.trim()),
      credentials: true,
    }),
  );
  app.use(express.json({ limit: '2mb' }));
  app.use(morgan(env.isProduction ? 'combined' : 'dev'));

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', uptime: process.uptime() });
  });

  app.use('/api/v1', api);

  if (webRoot) {
    // The Flutter shell is served under the API's own domain.
    app.use(express.static(webRoot, { index: false }));
    app.get('*', (req, res, next) => {
      // Never swallow API 404s: those must stay JSON for the mobile clients.
      if (req.path.startsWith('/api/')) return next();
      return res.sendFile(path.join(webRoot, 'index.html'));
    });
    // eslint-disable-next-line no-console
    console.log(`Serving the web app from ${webRoot}`);
  } else {
    app.get('/', (_req, res) => {
      res.json({
        name: 'ERP Inventory & Sales API',
        version: '1.0.0',
        api: '/api/v1',
        docs: 'See erp/README.md',
      });
    });
  }

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
