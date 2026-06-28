# Бэкенд ЛК Интерра
FROM node:20-bookworm-slim

WORKDIR /app

# Зависимости (better-sqlite3 ставится из prebuilt-бинарника для glibc linux)
COPY package*.json ./
RUN npm ci --omit=dev

# Исходники
COPY src ./src
COPY public ./public

ENV NODE_ENV=production
ENV PORT=8080
ENV DB_PATH=/data/interra.sqlite

# Том для БД (чтобы переживала перезапуски)
VOLUME ["/data"]

EXPOSE 8080
CMD ["node", "src/index.js"]
