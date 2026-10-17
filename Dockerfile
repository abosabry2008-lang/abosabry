# ===========================================================================
# ERP — single container: REST API + the compiled Flutter web app.
#
# Build from the REPOSITORY ROOT (the build context needs both erp/backend
# and erp/web):
#
#   docker build -t erp .
#   docker run -p 8000:4000 -e DATABASE_URL=postgresql://... erp
#
# The web app is served from the same origin as the API, so there is exactly
# one URL and no CORS configuration involved.
# ===========================================================================

# ------------------------------- build stage ------------------------------
FROM node:20-bookworm-slim AS build
WORKDIR /app

COPY erp/backend/package*.json ./
RUN npm ci --include=dev

COPY erp/backend/prisma ./prisma
RUN npx prisma generate

COPY erp/backend/tsconfig.json ./
COPY erp/backend/src ./src
RUN npm run build

# ------------------------------ runtime stage -----------------------------
FROM node:20-bookworm-slim AS runtime

# openssl: required by the Prisma query engine; ca-certificates: TLS to Neon
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY erp/backend/package*.json ./
# dev dependencies are kept on purpose so the Prisma CLI is available to sync
# the schema (there are no migration files; we use `prisma db push`).
RUN npm ci --include=dev

COPY erp/backend/prisma ./prisma
RUN npx prisma generate

COPY --from=build /app/dist ./dist

# The compiled Flutter web app (see erp/deploy/build_web.ps1)
COPY erp/web ./web
ENV WEB_ROOT=/app/web

ENV NODE_ENV=production
ENV PORT=4000
EXPOSE 4000

# Sync the schema (with a couple of retries, managed Postgres can cold-start)
# and then serve the API + web app.
CMD ["sh", "-c", "for i in 1 2 3; do npx prisma db push --skip-generate && break || sleep 5; done; exec node dist/server.js"]
