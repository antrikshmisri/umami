# Install dependencies only when needed
FROM node:22-alpine AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN npm install -g pnpm
RUN pnpm install --frozen-lockfile

# Rebuild the source code only when needed
FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG DATABASE_TYPE
ARG BASE_PATH

ENV DATABASE_TYPE=$DATABASE_TYPE
ENV BASE_PATH=$BASE_PATH

ENV NEXT_TELEMETRY_DISABLED=1

RUN npm run build-docker

# Production image, copy all the files and run next
FROM node:22-alpine AS runner
WORKDIR /app

ARG NODE_OPTIONS

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_OPTIONS=$NODE_OPTIONS

# The following lines for adding a custom user are removed as they conflict with OpenShift
# RUN addgroup --system --gid 1001 nodejs
# RUN adduser --system --uid 1001 nextjs

RUN npm install -g pnpm

RUN set -x \
    && apk add --no-cache curl

# Script dependencies
RUN pnpm add npm-run-all dotenv prisma@6.7.0

# This chown is removed as the 'nextjs' user is no longer created
# # Permissions for prisma
# RUN chown -R nextjs:nodejs node_modules/.pnpm/

# This command sets the correct group permissions for the OpenShift environment
RUN chgrp -R 0 /app && \
    chmod -R g+rwX /app

# The '--chown' flag is removed from all COPY commands
COPY --from=builder /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/scripts ./scripts

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

# Custom routes
RUN mv ./.next/routes-manifest.json ./.next/routes-manifest-orig.json

# The USER directive is removed to let OpenShift manage the user
# USER nextjs

EXPOSE 3000

ENV HOSTNAME=0.0.0.0
ENV PORT=3000

CMD ["pnpm", "start-docker"]