import { Request, Response, NextFunction } from 'express';
import { AppError } from '../domain/errors.js';
import { logger } from '../infrastructure/logger.js';
import { getRequestId } from '../infrastructure/async-context.js';
import { sendServerErrorAlert } from '../infrastructure/telegram.js';

export function errorHandlerMiddleware(
  err: Error,
  req: Request,
  res: Response,
  _next: NextFunction
) {
  if (err instanceof AppError) {
    logger.warn({ err, details: err.details }, `[AppError ${err.statusCode}]: ${err.message}`);
    return res.status(err.statusCode).json({
      error: err.message,
      ...(err.details ? { details: err.details } : {}),
    });
  }

  logger.error({ err }, '[UnhandledError]: Internal server error');
  sendServerErrorAlert(req.path, req.method, getRequestId() || 'n/a', err.message);

  return res.status(500).json({ error: 'Внутренняя ошибка сервера' });
}
