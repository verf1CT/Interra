import { Router } from 'express';
import { requireAdmin } from '../middleware/auth.js';
import { stats, recentBroadcasts, broadcastStats, createScheduled, listScheduled, cancelScheduled } from '../db.js';
import { fcmEnabled } from '../fcm.js';
import { runBroadcast } from '../broadcast.js';

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

/** общая валидация тела рассылки. Возвращает строку-ошибку или null. */
function validateBroadcast({ title, body, target, imageUrl, link }) {
  if (!title || !body) return 'title и body обязательны';
  if (!target || !['all', 'segment', 'login'].includes(target.type)) {
    return "target.type должен быть 'all', 'segment' или 'login'";
  }
  if ((target.type === 'segment' || target.type === 'login') && !target.value) {
    return 'для segment/login нужен target.value';
  }
  for (const [name, val] of Object.entries({ imageUrl, link })) {
    if (val != null && val !== '' && (typeof val !== 'string' || !/^https:\/\//i.test(val))) {
      return `${name} должен быть https-ссылкой`;
    }
  }
  return null;
}

/**
 * POST /api/admin/broadcast
 * Тело: {
 *   title, body,
 *   target: { type: 'all'|'segment'|'login', value? },
 *   data?: object,
 *   imageUrl?: string,  // https-картинка в уведомлении (rich push)
 *   link?: string,      // https-ссылка, открывается по тапу (кладётся в data.link)
 *   sendAt?: string     // если задано — не слать сейчас, а запланировать на это время
 * }
 */
adminRouter.post('/broadcast', async (req, res) => {
  const { title, body, target, data, imageUrl, link, sendAt } = req.body || {};

  const err = validateBroadcast({ title, body, target, imageUrl, link });
  if (err) return res.status(400).json({ error: err });

  // запланированная рассылка
  if (sendAt != null && sendAt !== '') {
    const when = new Date(sendAt);
    if (Number.isNaN(when.getTime())) {
      return res.status(400).json({ error: 'sendAt — некорректная дата/время' });
    }
    if (when.getTime() <= Date.now()) {
      return res.status(400).json({ error: 'sendAt должен быть в будущем' });
    }
    const r = createScheduled({ title, body, data, imageUrl, link, target, sendAt: when.toISOString() });
    return res.json({ ok: true, scheduled: true, id: r.lastInsertRowid, sendAt: when.toISOString() });
  }

  // немедленная отправка
  const result = await runBroadcast({ title, body, target, data, imageUrl, link });
  res.json({ ok: true, ...result });
});

/** GET /api/admin/scheduled — ожидающие отправки рассылки. */
adminRouter.get('/scheduled', (req, res) => {
  res.json({ scheduled: listScheduled() });
});

/** POST /api/admin/scheduled/:id/cancel — отменить запланированную рассылку. */
adminRouter.post('/scheduled/:id/cancel', (req, res) => {
  const r = cancelScheduled(Number(req.params.id));
  res.json({ ok: true, canceled: r.changes });
});
