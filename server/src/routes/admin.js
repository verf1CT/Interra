import { Router } from 'express';
import { requireAdmin } from '../middleware/auth.js';
import { selectTokens, logBroadcast, stats, recentBroadcasts, broadcastStats } from '../db.js';
import { sendToTokens, fcmEnabled } from '../fcm.js';

export const adminRouter = Router();
adminRouter.use(requireAdmin);

/** GET /api/admin/stats - сводка по устройствам, аналитика и последние рассылки. */
adminRouter.get('/stats', (req, res) => {
  res.json({
    fcmEnabled: fcmEnabled(),
    devices: stats(),
    totals: broadcastStats(),
    broadcasts: recentBroadcasts(),
  });
});

/**
 * POST /api/admin/broadcast
 * Тело: {
 *   title, body,
 *   target: { type: 'all'|'segment'|'login', value? },
 *   data?: object,
 *   imageUrl?: string,  // https-картинка в уведомлении (rich push)
 *   link?: string       // https-ссылка, открывается по тапу (кладётся в data.link)
 * }
 */
adminRouter.post('/broadcast', async (req, res) => {
  const { title, body, target, data, imageUrl, link } = req.body || {};

  if (!title || !body) {
    return res.status(400).json({ error: 'title и body обязательны' });
  }
  if (!target || !['all', 'segment', 'login'].includes(target.type)) {
    return res.status(400).json({ error: "target.type должен быть 'all', 'segment' или 'login'" });
  }
  if ((target.type === 'segment' || target.type === 'login') && !target.value) {
    return res.status(400).json({ error: 'для segment/login нужен target.value' });
  }
  // необязательные url — но если заданы, только https
  for (const [name, val] of Object.entries({ imageUrl, link })) {
    if (val != null && val !== '' && (typeof val !== 'string' || !/^https:\/\//i.test(val))) {
      return res.status(400).json({ error: `${name} должен быть https-ссылкой` });
    }
  }

  const tokens = selectTokens(target);
  if (tokens.length === 0) {
    return res.json({ ok: true, recipients: 0, successCount: 0, failureCount: 0, note: 'нет получателей' });
  }

  // link уходит в data, чтобы приложение открыло его по тапу
  const outData = { ...(data || {}), ...(link ? { link } : {}) };

  const { successCount, failureCount } = await sendToTokens(tokens, {
    title,
    body,
    data: outData,
    imageUrl: imageUrl || undefined,
  });

  logBroadcast({
    title,
    body,
    // сохраняем image/link в журнале, чтобы показывать их в истории/аналитике
    data: { ...outData, ...(imageUrl ? { image: imageUrl } : {}) },
    target,
    recipients: tokens.length,
    successCount,
    failureCount,
  });

  res.json({ ok: true, recipients: tokens.length, successCount, failureCount });
});
