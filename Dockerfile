# ---- base (with pnpm) ----
FROM ghcr.io/railwayapp/nixpacks:ubuntu-1745885067 AS base
WORKDIR /app

# Avoid baking secrets into the image. Use Coolify env panel instead.
# (Remove ARG/ENV for secrets from the Dockerfile.)

# Pin Puppeteer's Chrome download to a known, absolute path instead of its
# default (~/.cache/puppeteer, resolved against whatever $HOME this base
# image's default user has). A fixed path is required so the runtime
# stage below can COPY it — otherwise it depends on this image's default
# user, which we don't control/know here, and a wrong guess means the
# runtime container has no browser at all despite install succeeding.
ENV PUPPETEER_CACHE_DIR=/app/.cache/puppeteer

# System libs Puppeteer's bundled Chromium needs at runtime. NOTE: we do
# NOT install the apt "chromium" package here — on Ubuntu 20.04+ (this
# base image) that package is a transitional stub that redirects to Snap,
# and Snap does not work inside Docker containers. Installing it silently
# gives you a binary that refuses to launch ("please install the chromium
# snap"), which is very likely why the CBE-legacy Puppeteer fallback has
# been failing. Puppeteer's own downloaded Chromium (left on, below) just
# needs these shared libraries to run — nothing snap-related.
RUN sudo apt-get update && sudo apt-get install -y --no-install-recommends \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libgbm1 libasound2t64 \
    libpangocairo-1.0-0 libxss1 libgtk-3-0 libxshmfence1 libglu1 curl wget \
    && sudo rm -rf /var/lib/apt/lists/*

COPY pnpm-lock.yaml package.json pnpm-workspace.yaml* ./
COPY prisma ./prisma

# ---- deps (install devDeps) ----
FROM base AS deps
# Force-install devDependencies regardless of NODE_ENV. This is also where
# Puppeteer's postinstall actually downloads Chrome, into
# $PUPPETEER_CACHE_DIR set above.
RUN --mount=type=cache,target=/root/.local/share/pnpm/store/v3 \
    pnpm install --frozen-lockfile --prod=false

# ---- build ----
FROM deps AS build
COPY . .
# Generate client & compile TS
RUN pnpm prisma generate && pnpm build
# Optionally prune to prod-only for runtime
RUN pnpm prune --prod

# ---- runtime ----
FROM ghcr.io/railwayapp/nixpacks:ubuntu-1745885067 AS runtime
WORKDIR /app
ENV NODE_ENV=production
# Must match the base/deps stage above — this is where verifyCBE.ts's
# Puppeteer launch will look for Chrome (Puppeteer checks this env var
# before falling back to its compiled-in default path).
ENV PUPPETEER_CACHE_DIR=/app/.cache/puppeteer

# Same system libs as base — deliberately no "chromium" apt package (see
# comment in the base stage above: it's a non-functional Snap stub on
# this Ubuntu-derived image). Puppeteer's own bundled Chromium is copied
# in via the cache-dir COPY below and only needs these shared libraries.
RUN sudo apt-get update && sudo apt-get install -y --no-install-recommends \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libgbm1 libasound2t64 \
    libpangocairo-1.0-0 libxss1 libgtk-3-0 libxshmfence1 libglu1 curl wget \
    && sudo rm -rf /var/lib/apt/lists/*

# Copy only what we need to run
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/prisma ./prisma
# The actual downloaded Chrome binary — was previously never copied into
# the runtime image at all, since it lives outside node_modules. Without
# this line the container has no browser regardless of the apt-chromium
# fix above, and the CBE-legacy Puppeteer fallback fails every time.
COPY --from=build /app/.cache/puppeteer ./.cache/puppeteer

# If you run migrations at startup:
# CMD ["sh", "-c", "pnpm prisma migrate deploy && node dist/index.js"]
CMD ["node", "dist/index.js"]
