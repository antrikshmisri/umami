# ---------------------------
# 1. Dependencies stage
# ---------------------------
FROM node:22-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN npm install -g pnpm
RUN pnpm install --frozen-lockfile

# ---------------------------
# 2. Build stage
# ---------------------------
FROM node:22-alpine AS builder
WORKDIR /app

# Bring in installed node_modules from deps
COPY --from=deps /app/node_modules ./node_modules

# Copy application source (this includes prisma/schema.prisma)
COPY . .

ARG DATABASE_TYPE
ARG BASE_PATH
ENV DATABASE_TYPE=$DATABASE_TYPE
ENV BASE_PATH=$BASE_PATH
ENV NEXT_TELEMETRY_DISABLED=1

# Generate Prisma client and engines at build time
RUN npx prisma generate

# Build the Next.js app
RUN npm run build-docker

# ---------------------------
# 3. Runtime stage
# ---------------------------
FROM node:22-alpine AS runner
WORKDIR /app

ARG NODE_OPTIONS
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_OPTIONS=$NODE_OPTIONS
ENV HOSTNAME=0.0.0.0
ENV PORT=3000

# Create non-root user
RUN addgroup --system --gid 1001 nodejs \
    && adduser --system --uid 1001 nextjs
RUN apk add --no-cache curl

# Copy built node_modules and app from builder
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/scripts ./scripts
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Custom routes tweak
RUN mv ./.next/routes-manifest.json ./.next/routes-manifest-orig.json

USER nextjs
EXPOSE 3000

CMD ["pnpm", "start-docker"]
