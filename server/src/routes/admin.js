import { Router } from 'express';
import { requireAdmin } from '../middleware/auth.js';
import { selectTokens, logBroadcast, stats, recentBroadcasts } from '../db.js';
import { sendToTokens, fcmEnabled } from '../fcm.js';

export const adminRouter = Router();
adminRouter.use(requireAdmin);

/** GET /api/admin/stats - сводка по устройствам и последние рассылки. */
adminRouter.get('/stats', (req, res) => {
  res.json({
    fcmEnabled: fcmEnabled(),
    devices: stats(),
    broadcasts: recentBroadcasts(),
  });
});

/**
 * POST /api/admin/broadcast
 * Тело: {
 *   title, body,
 *   target: { type: 'all'|'segment'|'login', value? },
 *   data?: object
 * }
 */
adminRouter.post('/broadcast', async (req, res) => {
  const { title, body, target, data } = req.body || {};

  if (!title || !body) {
    return res.status(400).json({ error: 'title и body обязательны' });
  }
  if (!target || !['all', 'segment', 'login'].includes(target.type)) {
    return res.status(400).json({ error: "target.type должен быть 'all', 'segment' или 'login'" });
  }
  if ((target.type === 'segment' || target.type === 'login') && !target.value) {
    return res.status(400).json({ error: 'для segment/login нужен target.value' });
  }

  const tokens = selectTokens(target);
  if (tokens.length === 0) {
    return res.json({ ok: true, recipients: 0, successCount: 0, failureCount: 0, note: 'нет получателей' });
  }

  const { successCount, failureCount } = await sendToTokens(tokens, { title, body, data });

  logBroadcast({
    title,
    body,
    data,
    target,
    recipients: tokens.length,
    successCount,
    failureCount,
  });

  res.json({ ok: true, recipients: tokens.length, successCount, failureCount });
});
