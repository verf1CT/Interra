# Бэкенд ЛК Интерра (TypeScript Edition)

Enterprise-ready бэкенд на **Node.js / Express / TypeScript**: хранит push-токены устройств, собирает метрики Prometheus, предоставляет интерактивную документацию **Scalar UI (OpenAPI 3.1)**, ведёт структурированное Pino-логирование и рассылает уведомления через Firebase Cloud Messaging (включая отложенные рассылки), плюс веб-панель оператора.

> 🚀 **Надо просто поднять сервер?** Переходите в [`ADMIN.md`](./ADMIN.md) — пошаговое руководство от чистого сервера до деплоя в Docker.

---

## 🏗 Архитектура и Устройство Кода

Проект построен по принципам **Clean Layered Architecture** со строгой типизацией TypeScript и полной валидацией входящих данных с помощью **Zod**.

```text
src/
├── config/             # Конфигурация (.env) с Zod-валидацией на старте (env.ts)
├── domain/             # Сущности, типы, Zod-схемы (schemas.ts) и кастомные ошибки (errors.ts)
├── infrastructure/     # Логирование Pino, метрики Prometheus, AsyncLocalStorage (requestId)
├── db/                 # Соединение с SQLite (better-sqlite3) и миграции (connection.ts)
├── docs/               # OpenAPI 3.1 спецификация и Scalar UI документация (openapi.ts)
├── repositories/       # Абстракция доступа к БД (device.repository.ts, broadcast.repository.ts)
├── services/           # Бизнес-логика (fcm.service.ts, broadcast.service.ts, scheduler.service.ts)
├── controllers/        # Обработка HTTP-запросов (device.controller.ts, admin.controller.ts, event.controller.ts)
├── middlewares/        # ErrorHandler, RateLimiter, RequestId, Auth, ValidateBody
├── routes/             # Маршруты Express (device.routes.ts, admin.routes.ts, event.routes.ts)
└── index.ts            # Главный модуль, Helmet, CORS, Graceful Shutdown
```

---

## 🛠 Технологии и Безопасность

- **Язык**: TypeScript (модули `NodeNext`, строгий режим `"strict": true`).
- **Интерактивная Документация**: **Scalar UI** + **OpenAPI 3.1** по адресу `/docs` и `/openapi.json`.
- **Сборщик / Скрипты**: `tsx watch` в dev-режиме, `tsc` для продакшн-билда в `dist/`.
- **Валидация**: **Zod** (валидация тела запросов, параметров и переменных окружения).
- **Логирование**: **Pino** (JSON-логи в продакшне, `pino-pretty` в dev-режиме) + сквозная трассировка запросов через `x-request-id`.
- **Метрики**: **prom-client** (Prometheus эндпоинт `/metrics`).
- **Безопасность**: **Helmet** (HTTP security headers) + **express-rate-limit** (антиспам).
- **Отказоустойчивость**: **Graceful Shutdown** по сигналам `SIGTERM`/`SIGINT` с аккуратным завершением процессов и закрытием SQLite.
- **Тестирование**: **Vitest** + **Supertest** (10/10 авто-тестов в `tests/api.test.ts`).

---

## 📡 API Справка

### 1. Для мобильного приложения

| Метод | Путь                      | Описание | Тело |
|-------|---------------------------|----------|------|
| POST  | `/api/devices/register`   | Регистрация FCM-токена устройства | `{ token, clientLogin?, platform?, appVersion?, segments?, prefs? }` |
| POST  | `/api/devices/unregister` | Удаление токена устройства | `{ token }` |
| POST  | `/api/events/opened`      | Отметка открытия пуша (для open-rate analytics) | `{ bid }` |

### 2. Документация, Системные и Метрики

| Метод | Путь            | Описание |
|-------|-----------------|----------|
| GET   | `/docs`         | **Интерактивная документация Scalar UI** (с возможностью тестирования запросов) |
| GET   | `/openapi.json` | Сырая спецификация OpenAPI 3.1 |
| GET   | `/healthz`      | Liveness проба (uptime сервера) |
| GET   | `/readyz`       | Readiness проба (проверка подключения к SQLite `SELECT 1`) |
| GET   | `/metrics`      | Prometheus формат метрик (HTTP latency, статус-коды, пуши) |

### 3. Для администратора / оператора (Заголовок `Authorization: Bearer <ADMIN_TOKEN>`)

| Метод | Путь                            | Описание |
|-------|---------------------------------|----------|
| GET   | `/api/admin/stats`              | Статистика устройств, сводка `totals` и история рассылок |
| POST  | `/api/admin/broadcast`          | Отправка немедленной или создание отложенной рассылки (`sendAt`) |
| GET   | `/api/admin/scheduled`          | Список всех ожидающих отложенных рассылок |
| POST  | `/api/admin/scheduled/:id/cancel` | Отмена отложенной рассылки по ID |

---

## 🚀 Скрипты Разработки и Сборки

Запуск доступен как напрямую через `npm`, так и через глобальное меню `make` из корня проекта:

```bash
# Из корня проекта (через Makefile):
make dev-server       # Запустить в dev-режиме
make test-server      # Запустить тесты Vitest
make build-server     # Собрать в dist/

# Или прямо в папке server/:
npm install
npm run dev           # Запуск в режиме разработки (tsx watch)
npm run typecheck     # Проверка типов TypeScript
npm run test          # Прогон интеграционных тестов Vitest
npm run build         # Продакшн-сборка TypeScript в папку dist/
npm start             # Запуск собранного проекта
```
