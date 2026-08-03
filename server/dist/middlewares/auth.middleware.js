import { config } from '../config/env.js';
import { UnauthorizedError } from '../domain/errors.js';
export function requireAdmin(req, _res, next) {
    if (!config.adminToken) {
        return next(new UnauthorizedError('ADMIN_TOKEN не настроен на сервере'));
    }
    const authHeader = req.headers.authorization || '';
    const tokenFromHeader = authHeader.startsWith('Bearer ')
        ? authHeader.slice(7)
        : null;
    const tokenFromQuery = req.query.token || null;
    const token = tokenFromHeader || tokenFromQuery;
    if (token !== config.adminToken) {
        return next(new UnauthorizedError('Неверный или отсутствующий токен авторизации'));
    }
    next();
}
