import { Router } from 'express';
import { upsertDevice, deleteDevice } from '../db.js';

export const devicesRouter = Router();

/**
 * POST /api/devices/register
 * Тело: { token, clientLogin?, platform?, appVersion?, segments?, prefs? }
 * Вызывается приложением при запуске и при смене токена/логина.
 */
devicesRouter.post('/register', (req, res) => {
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
 * Вызывается при выходе из аккаунта / отключении уведомлений.
 */
devicesRouter.post('/unregister', (req, res) => {
  const { token } = req.body || {};
  if (!token) return res.status(400).json({ error: 'token обязателен' });
  deleteDevice(token);
  res.json({ ok: true });
});
