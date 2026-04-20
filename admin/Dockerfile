# syntax=docker/dockerfile:1.6
# =============================================================================
# Rishfy Admin Dashboard — Next.js 14
# =============================================================================

# ---- Base ---------------------------------------------------------
FROM node:20-alpine AS base
RUN apk add --no-cache libc6-compat
WORKDIR /app
ENV NODE_ENV=production

# ---- Dependencies ------------------------------------------------
FROM base AS deps
COPY package.json package-lock.json* ./
RUN npm ci --ignore-scripts && npm cache clean --force

# ---- Development image -------------------------------------------
FROM base AS development
ENV NODE_ENV=development
COPY --from=deps /app/node_modules ./node_modules
COPY . .
EXPOSE 3000
CMD ["npm", "run", "dev"]

# ---- Builder -----------------------------------------------------
FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# ---- Production image --------------------------------------------
FROM node:20-alpine AS production
WORKDIR /app
ENV NODE_ENV=production

RUN addgroup -S nodejs -g 1001 \
 && adduser -S nextjs -u 1001

COPY --from=builder /app/public ./public

# Uses Next.js standalone output mode (enable in next.config.js if desired)
COPY --from=builder --chown=nextjs:nodejs /app/.next ./.next
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

USER nextjs
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD wget -q --spider http://localhost:3000/api/health || exit 1

CMD ["npm", "start"]
