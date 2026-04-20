# syntax=docker/dockerfile:1.6
# =============================================================================
# user-service Dockerfile
# =============================================================================

# ---- Base ---------------------------------------------------------
FROM node:20-alpine AS base
RUN apk add --no-cache tini dumb-init
WORKDIR /app
ENV NODE_ENV=production

# ---- Dependencies (cached layer) ----------------------------------
FROM base AS deps
COPY package.json package-lock.json* ./
RUN npm ci --ignore-scripts && npm cache clean --force

# ---- Development image --------------------------------------------
FROM base AS development
ENV NODE_ENV=development
COPY --from=deps /app/node_modules ./node_modules
COPY . .
EXPOSE 8082 50052
CMD ["npx", "tsx", "watch", "src/server.ts"]

# ---- Builder ------------------------------------------------------
FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build && npm prune --production

# ---- Production image ---------------------------------------------
FROM node:20-alpine AS production
RUN apk add --no-cache tini
WORKDIR /app
ENV NODE_ENV=production

# Create a non-root user
RUN addgroup -S rishfy && adduser -S rishfy -G rishfy

COPY --from=builder --chown=rishfy:rishfy /app/dist ./dist
COPY --from=builder --chown=rishfy:rishfy /app/node_modules ./node_modules
COPY --from=builder --chown=rishfy:rishfy /app/package.json ./

USER rishfy
EXPOSE 8082 50052

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8082/health', r => process.exit(r.statusCode === 200 ? 0 : 1))"

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/server.js"]
