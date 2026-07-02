import { Router } from 'express';
import { upsertDevice, deleteDevice } from '../db.js';

export const devicesRouter = Router();

// простой антиспам: не больше N запросов с одного IP за окно. защищает базу
// токенов от заваливания без внешних зависимостей (для одного инстанса)
const RATE_MAX = 30;
const RATE_WINDOW_MS = 60_000;
const hits = new Map(); // ip -> { count, resetAt }

function rateLimit(req, res, next) {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const now = Date.now();
  const rec = hits.get(ip);
  if (!rec || now > rec.resetAt) {
    hits.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return next();
  }
  if (rec.count >= RATE_MAX) {
    return res.status(429).json({ error: 'Слишком много запросов, попробуйте позже' });
  }
  rec.count++;
  next();
}

// периодически чистим старые записи, чтобы Map не рос бесконечно
setInterval(() => {
  const now = Date.now();
  for (const [ip, rec] of hits) if (now > rec.resetAt) hits.delete(ip);
}, RATE_WINDOW_MS).unref?.();

/**
 * POST /api/devices/register
 * Тело: { token, clientLogin?, platform?, appVersion?, segments?, prefs? }
 * Вызывается приложением при запуске и при смене токена/логина
 */
devicesRouter.post('/register', rateLimit, (req, res) => {
  const { token, clientLogin, platform, appVersion, segments, prefs } = req.body || {};
  if (!token || typeof token !== 'string') {
    return res.status(400).json({ error: 'token обязателен' });
  }
  if (segments && !Array.isArray(segments)) {
    return res.status(400).json({ error: 'segments должен быть массивом' });
  }

  const device = upsertDevice({ token, clientLogin, platform, appVersion, segments, prefs });
  res.json({ ok: true, deviceId: device.id });
});

/**
 * POST /api/devices/unregister
 * Тело: { token }
 * Вызывается при выходе из аккаунта / отключении уведомлений
 */
devicesRouter.post('/unregister', (req, res) => {
  const { token } = req.body || {};
  if (!token) return res.status(400).json({ error: 'token обязателен' });
  deleteDevice(token);
  res.json({ ok: true });
});
