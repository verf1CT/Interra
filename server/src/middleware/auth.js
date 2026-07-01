import { timingSafeEqual, createHash } from 'node:crypto';
import { config } from '../config.js';

// Сравниваем sha256-хеши (одинаковая длина буферов — требование
// timingSafeEqual), чтобы сравнение шло за постоянное время.
const sha = (s) => createHash('sha256').update(s, 'utf8').digest();

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
  if (!timingSafeEqual(sha(token), sha(config.adminToken))) {
    return res.status(401).json({ error: 'Неверный админ-токен' });
  }
  next();
}
