# =====================================================================
#  ArtisanEye Backend — Dockerfile
#  Multi-stage build: deps → build → production image
#  Final image: ~180MB (node:20-alpine)
# =====================================================================

# ── Stage 1: install all dependencies ────────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app

COPY package*.json ./
# Use npm install (not npm ci) since package-lock.json is gitignored
# In production, commit your package-lock.json to enable npm ci for reproducible builds
RUN npm install --only=production

# ── Stage 2: generate Prisma client ──────────────────────────────────
FROM node:20-alpine AS prisma
WORKDIR /app

COPY package*.json ./
COPY prisma ./prisma
RUN npm install && npx prisma generate

# ── Stage 3: production image ─────────────────────────────────────────
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production

# Security: run as non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser  --system --uid 1001 artisaneye

# Copy production deps
COPY --from=deps   /app/node_modules ./node_modules
# Copy generated Prisma client
COPY --from=prisma /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=prisma /app/node_modules/@prisma ./node_modules/@prisma

# Copy source
COPY prisma ./prisma
COPY src    ./src
COPY public ./public

# Create uploads dir (used as fallback if Cloudinary not configured)
RUN mkdir -p uploads/photos && chown -R artisaneye:nodejs uploads

USER artisaneye

EXPOSE 4000

# Run migrations then start server
CMD ["sh", "-c", "npx prisma migrate deploy && node src/index.js"]
