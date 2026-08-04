FROM mcr.microsoft.com/devcontainers/javascript-node:1-20-bullseye

# Установка системных пакетов для SQLite и разработке
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends sqlite3 libsqlite3-dev build-essential python3

# Глобальные npm утилиты
RUN npm install -g tsx typescript
