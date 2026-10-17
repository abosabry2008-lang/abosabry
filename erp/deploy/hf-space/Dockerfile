# ===========================================================================
# Hugging Face Space — ERP API + web app (Docker SDK).
#
# This image pulls the application from GitHub and builds it, so the Space
# stays in sync with the repository. Re-trigger a build after pushing code:
# Space page -> Settings -> Factory rebuild.
#
# The Space must declare `app_port: 7860` in its README front matter.
# ===========================================================================

FROM node:20-bookworm-slim AS build

# git: to fetch the application; openssl/ca-certificates: Prisma + TLS to Neon
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
ARG REPO=https://github.com/abosabry2008-lang/abosabry.git
ARG BRANCH=main
RUN git clone --depth 1 --branch "$BRANCH" "$REPO" .

WORKDIR /src/erp/backend
RUN npm ci --include=dev
RUN npx prisma generate && npm run build

# ------------------------------ runtime stage -----------------------------
FROM node:20-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY --from=build /src/. /src/

WORKDIR /src/erp/backend
# dev dependencies are kept so the Prisma CLI can sync the schema on boot
RUN npm ci --include=dev && npx prisma generate

ENV NODE_ENV=production
ENV PORT=7860
ENV WEB_ROOT=/src/erp/web
EXPOSE 7860

# Sync the schema, then serve the API + web app on the same origin.
CMD ["sh", "-c", "for i in 1 2 3; do npx prisma db push --skip-generate && break || sleep 5; done; exec node dist/server.js"]
