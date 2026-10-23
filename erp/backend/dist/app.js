"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createApp = createApp;
const cors_1 = __importDefault(require("cors"));
const express_1 = __importDefault(require("express"));
const fs_1 = __importDefault(require("fs"));
const helmet_1 = __importDefault(require("helmet"));
const morgan_1 = __importDefault(require("morgan"));
const path_1 = __importDefault(require("path"));
const env_1 = require("./config/env");
const error_handler_1 = require("./middleware/error-handler");
const routes_1 = __importDefault(require("./routes"));
/**
 * Finds the compiled Flutter web app, which is served from the same origin as
 * the API when it is present (one URL, no CORS, works on any container host).
 *
 * Looks at `WEB_ROOT` first, then the two layouts we ship in:
 *   - `/app/web`  (Docker image built from the repo root Dockerfile)
 *   - `erp/web`   (running straight from the repository)
 */
function findWebRoot() {
    const candidates = [
        process.env.WEB_ROOT,
        path_1.default.resolve(__dirname, '../web'),
        path_1.default.resolve(__dirname, '../../web'),
    ].filter((value) => Boolean(value && value.trim()));
    for (const candidate of candidates) {
        if (fs_1.default.existsSync(path_1.default.join(candidate, 'index.html'))) {
            return candidate;
        }
    }
    return null;
}
function createApp() {
    const app = (0, express_1.default)();
    const webRoot = findWebRoot();
    app.disable('x-powered-by');
    // CSP is disabled on purpose: the Flutter/CanvasKit bundle instantiates
    // WebAssembly, which needs `wasm-unsafe-eval`. Only our own assets are served.
    app.use((0, helmet_1.default)({ contentSecurityPolicy: false }));
    app.use((0, cors_1.default)({
        origin: env_1.env.corsOrigin === '*' ? true : env_1.env.corsOrigin.split(',').map((value) => value.trim()),
        credentials: true,
    }));
    app.use(express_1.default.json({ limit: '2mb' }));
    app.use((0, morgan_1.default)(env_1.env.isProduction ? 'combined' : 'dev'));
    app.get('/health', (_req, res) => {
        res.json({ status: 'ok', uptime: process.uptime() });
    });
    app.use('/api/v1', routes_1.default);
    if (webRoot) {
        // The Flutter shell is served under the API's own domain.
        app.use(express_1.default.static(webRoot, { index: false }));
        app.get('*', (req, res, next) => {
            // Never swallow API 404s: those must stay JSON for the mobile clients.
            if (req.path.startsWith('/api/'))
                return next();
            return res.sendFile(path_1.default.join(webRoot, 'index.html'));
        });
        // eslint-disable-next-line no-console
        console.log(`Serving the web app from ${webRoot}`);
    }
    else {
        app.get('/', (_req, res) => {
            res.json({
                name: 'ERP Inventory & Sales API',
                version: '1.0.0',
                api: '/api/v1',
                docs: 'See erp/README.md',
            });
        });
    }
    app.use(error_handler_1.notFoundHandler);
    app.use(error_handler_1.errorHandler);
    return app;
}
//# sourceMappingURL=app.js.map