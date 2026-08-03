import { AppError } from '../domain/errors.js';
import { logger } from '../infrastructure/logger.js';
export function errorHandlerMiddleware(err, _req, res, _next) {
    if (err instanceof AppError) {
        logger.warn({ err, details: err.details }, `[AppError ${err.statusCode}]: ${err.message}`);
        return res.status(err.statusCode).json({
            error: err.message,
            ...(err.details ? { details: err.details } : {}),
        });
    }
    logger.error({ err }, '[UnhandledError]: Internal server error');
    return res.status(500).json({ error: 'Внутренняя ошибка сервера' });
}
