import express from 'express';
import { BotEngine } from '../bot/botEngine.js';
import { TelegramClient } from '../bot/telegramClient.js';
import { TelegramHandler } from '../bot/telegramHandler.js';
import { MaxClient } from '../bot/maxClient.js';
import { MaxHandler } from '../bot/maxHandler.js';

export const botRouter = express.Router();

const engine = new BotEngine();
const tgClient = new TelegramClient(process.env.TELEGRAM_BOT_TOKEN);
const tgHandler = new TelegramHandler(engine, tgClient);

const maxClient = new MaxClient(process.env.MAX_BOT_TOKEN);
const maxHandler = new MaxHandler(engine, maxClient);

// Эндпоинт статуса бота и сценария
botRouter.get('/status', (req, res) => {
  res.json({
    ok: true,
    name: 'Интерра Виртуальный Помощник (MAX & Multi-channel)',
    maxConfigured: maxClient.isConfigured,
    telegramConfigured: tgClient.isConfigured,
    totalSteps: Object.keys(engine.scenario).length,
    activeSessions: engine.sessions.size,
    version: '1.0.0'
  });
});

// Платформа MAX Webhook (business.max.ru / platform-api2.max.ru)
botRouter.post('/max/webhook', async (req, res) => {
  res.status(200).send('OK');

  if (req.body) {
    try {
      await maxHandler.handleUpdate(req.body);
    } catch (err) {
      console.error('[MAX Bot Webhook Error]', err);
    }
  }
});

// Telegram Webhook (если включен)
botRouter.post('/webhook', async (req, res) => {
  res.status(200).send('OK');

  if (req.body) {
    try {
      await tgHandler.handleUpdate(req.body);
    } catch (err) {
      console.error('[Bot Webhook Error]', err);
    }
  }
});

// Эндпоинт симуляции для тестирования
botRouter.post('/simulate', async (req, res) => {
  const { userId = 'web-test-user', action = 'start', stepId, text, buttonValue } = req.body;

  try {
    let result;
    if (action === 'start') {
      result = await engine.handleStart(userId);
    } else if (action === 'click') {
      result = await engine.handleButtonClick(userId, stepId, buttonValue);
    } else if (action === 'text') {
      result = await engine.handleTextInput(userId, text);
    } else {
      return res.status(400).json({ error: 'Unknown action' });
    }

    res.json({ ok: true, session: engine.getSession(userId), result });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});
