# Production image, copy all the files and run next
FROM node:22-alpine AS runner
WORKDIR /app

ARG NODE_OPTIONS

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_OPTIONS=$NODE_OPTIONS

# ---- START OF CHANGES ----

# 1. REMOVED the creation of a custom user and group.
# RUN addgroup --system --gid 1001 nodejs
# RUN adduser --system --uid 1001 nextjs

RUN npm install -g pnpm

RUN set -x \
    && apk add --no-cache curl

# Script dependencies
RUN pnpm add npm-run-all dotenv prisma@6.7.0

# 2. REMOVED the specific 'chown' for the 'nextjs' user.
# # Permissions for prisma
# RUN chown -R nextjs:nodejs node_modules/.pnpm/

# 3. ADDED permissions for OpenShift. This makes the directory writable
#    by the root group (gid 0), which is what OpenShift uses.
RUN chgrp -R 0 /app && \
    chmod -R g+rwX /app

# 4. REMOVED '--chown' from all COPY commands.
COPY --from=builder /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/scripts ./scripts

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

# Custom routes
RUN mv ./.next/routes-manifest.json ./.next/routes-manifest-orig.json

# 5. REMOVED the USER directive. OpenShift will set the user automatically.
# USER nextjs

# ---- END OF CHANGES ----

EXPOSE 3000

ENV HOSTNAME=0.0.0.0
ENV PORT=3000

CMD ["pnpm", "start-docker"]