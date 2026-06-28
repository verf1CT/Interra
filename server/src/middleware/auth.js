import { config } from '../config.js';

/**
 * Простая защита админ-эндпоинтов через bearer-токен (ADMIN_TOKEN).
 * Заголовок: Authorization: Bearer <ADMIN_TOKEN>
 */
export function requireAdmin(req, res, next) {
  if (!config.adminToken) {
    return res.status(503).json({ error: 'ADMIN_TOKEN не настроен на сервере' });
  }
  const header = req.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : header;
  if (token !== config.adminToken) {
    return res.status(401).json({ error: 'Неверный админ-токен' });
  }
  next();
}
