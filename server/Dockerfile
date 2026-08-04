# =========================================================
# Multi-stage Dockerfile for Interra Push Server (TypeScript)
# =========================================================

# --- Stage 1: Build TypeScript ---
FROM node:20-alpine AS builder

WORKDIR /app

# Системные пакеты для компиляции native C++ модуля better-sqlite3
RUN apk add --no-cache python3 make g++

COPY package*.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
COPY public ./public

RUN npm run build

# --- Stage 2: Production Runtime ---
FROM node:20-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080

# Инструменты сборки для npm ci --only=production
RUN apk add --no-cache python3 make g++
COPY package*.json ./
RUN npm ci --only=production && \
    apk del python3 make g++

# Копируем скомпилированный код и статику админки из Stage 1
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

# Создаем папку для хранения SQLite базы данных
RUN mkdir -p /app/data

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/healthz || exit 1

CMD ["node", "dist/index.js"]
