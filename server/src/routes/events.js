import { Router } from 'express';
import { incrementOpens } from '../db.js';

export const eventsRouter = Router();

/**
 * POST /api/events/opened
 * Тело: { bid }
 * Приложение сообщает, что пользователь открыл уведомление рассылки (тап по
 * пушу с data.bid). Без токена — это анонимная метрика; считаем open-rate.
 */
eventsRouter.post('/opened', (req, res) => {
  const id = Number((req.body || {}).bid);
  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ error: 'bid обязателен' });
  }
  incrementOpens(id);
  res.json({ ok: true });
});
