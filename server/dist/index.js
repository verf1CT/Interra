import path from 'node:path';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import { config } from './config/env.js';
import { logger } from './infrastructure/logger.js';
import { register, httpRequestDurationMicroseconds } from './infrastructure/metrics.js';
import { requestIdMiddleware } from './middlewares/request-id.middleware.js';
import { errorHandlerMiddleware } from './middlewares/error-handler.middleware.js';
import { devicesRouter } from './routes/device.routes.js';
import { adminRouter } from './routes/admin.routes.js';
import { eventsRouter } from './routes/event.routes.js';
import { schedulerService } from './services/scheduler.service.js';
import { db } from './db/connection.js';
export const app = express();
// За обратным прокси (nginx) доверяем первому хопу
app.set('trust proxy', 1);
// Security & Middlewares
app.use(helmet({
    contentSecurityPolicy: false, // позволяет загружаться админ-панели и встроенным скриптам
}));
app.use(cors({ origin: config.allowedOrigins }));
app.use(express.json({ limit: '64kb' }));
app.use(requestIdMiddleware);
// Prometheus HTTP Metrics Middleware
app.use((req, res, next) => {
    const start = process.hrtime();
    res.on('finish', () => {
        const diff = process.hrtime(start);
        const durationInSeconds = diff[0] + diff[1] / 1e9;
        const routeName = req.route?.path ? `${req.baseUrl}${req.route.path}` : req.baseUrl || req.path;
        httpRequestDurationMicroseconds.observe({ method: req.method, route: routeName, code: res.statusCode.toString() }, durationInSeconds);
    });
    next();
});
// Статика админ-панели
app.use(express.static(path.join(config.serverRoot, 'public')));
// Health & System Routes
app.get('/healthz', (_req, res) => {
    res.json({ status: 'ok', uptime: process.uptime() });
});
app.get('/readyz', (_req, res) => {
    try {
        const row = db.prepare('SELECT 1 AS ok').get();
        if (row && row.ok === 1) {
            return res.json({ status: 'ready', db: 'connected' });
        }
        return res.status(503).json({ status: 'not_ready', db: 'error' });
    }
    catch (err) {
        return res.status(503).json({ status: 'not_ready', error: err.message });
    }
});
app.get('/metrics', async (_req, res) => {
    try {
        res.set('Content-Type', register.contentType);
        res.end(await register.metrics());
    }
    catch (err) {
        res.status(500).end(err);
    }
});
// API Routes
app.use('/api/devices', devicesRouter);
app.use('/api/admin', adminRouter);
app.use('/api/events', eventsRouter);
// Centralized Error Handling
app.use(errorHandlerMiddleware);
// Server Start & Graceful Shutdown
let server;
if (config.nodeEnv !== 'test') {
    server = app.listen(config.port, () => {
        logger.info(`🚀 [server] ЛК Интерра backend запущен на http://localhost:${config.port}`);
        logger.info(`📊 [metrics] Prometheus метрики: http://localhost:${config.port}/metrics`);
        logger.info(`🩺 [health] Liveness/Readiness: http://localhost:${config.port}/healthz`);
        schedulerService.start();
    });
    const gracefulShutdown = (signal) => {
        logger.info({ signal }, 'Получен сигнал завершения. Запуск Graceful Shutdown...');
        schedulerService.stop();
        if (server) {
            server.close(() => {
                logger.info('HTTP-сервер остановлен. Закрываем подключение к SQLite...');
                try {
                    db.close();
                    logger.info('Соединение с БД успешно закрыто. Процесс завершён.');
                    process.exit(0);
                }
                catch (err) {
                    logger.error({ err }, 'Ошибка при закрытии БД');
                    process.exit(1);
                }
            });
        }
        else {
            process.exit(0);
        }
    };
    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
    process.on('SIGINT', () => gracefulShutdown('SIGINT'));
}
