import express, { Router } from 'express';
import { saveDump } from '../db.js';

export const debugRouter = Router();

// дамп шлют руками из скрытого меню, поэтому лимит жёсткий: защита от мусора
const RATE_MAX = 10;
const RATE_WINDOW_MS = 60 * 60_000;
const hits = new Map(); // ip -> { count, resetAt }

function rateLimit(req, res, next) {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const now = Date.now();
  const rec = hits.get(ip);
  if (!rec || now > rec.resetAt) {
    hits.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return next();
  }
  if (rec.count >= RATE_MAX) return res.status(429).json({ error: 'Слишком много дампов, попробуйте позже' });
  rec.count++;
  next();
}

setInterval(() => {
  const now = Date.now();
  for (const [ip, rec] of hits) if (now > rec.resetAt) hits.delete(ip);
}, RATE_WINDOW_MS).unref?.();

/**
 * POST /api/debug/dump
 * Тело: text/plain - страницы кабинета, токены сессии в приложении уже замазаны.
 * Заголовки X-App-Version и X-Platform - для подписи в списке
 */
debugRouter.post('/dump', rateLimit, express.text({ type: '*/*', limit: '1mb' }), (req, res) => {
  const body = typeof req.body === 'string' ? req.body : '';
  if (body.trim().length < 20) return res.status(400).json({ error: 'пустой дамп' });
  const id = saveDump({
    platform: String(req.get('x-platform') || '').slice(0, 20),
    appVersion: String(req.get('x-app-version') || '').slice(0, 40),
    body,
  });
  res.json({ ok: true, id });
});
