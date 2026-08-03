import { config } from '../config/env.js';
import { logger } from './logger.js';
import { broadcastService } from '../services/broadcast.service.js';

export interface TelegramInlineButton {
  text: string;
  url?: string;
  callback_data?: string;
}

export interface TelegramReplyMarkup {
  inline_keyboard?: TelegramInlineButton[][];
}

/**
 * Отправляет сообщение в Telegram-чат администраторов.
 */
export async function sendTelegramAlert(text: string, replyMarkup?: TelegramReplyMarkup): Promise<boolean> {
  const { telegramBotToken, telegramChatId } = config;

  if (!telegramBotToken || !telegramChatId) {
    return false;
  }

  try {
    const url = `https://api.telegram.org/bot${telegramBotToken}/sendMessage`;
    const body: Record<string, unknown> = {
      chat_id: telegramChatId,
      text,
      parse_mode: 'HTML',
      disable_web_page_preview: true,
    };

    if (replyMarkup) {
      body.reply_markup = replyMarkup;
    }

    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const errText = await response.text();
      logger.error({ errText, status: response.status }, 'Ошибка отправки Telegram алерта');
      return false;
    }

    return true;
  } catch (err) {
    logger.error({ err }, 'Ошибка сети при отправке Telegram алерта');
    return false;
  }
}

/**
 * Шаблон сообщения при запуске сервера с интерактивными кнопками
 */
export function sendServerBootAlert(port: number, env: string): void {
  const isProd = env === 'production' || config.serverBaseUrl.includes('push.interra.ru');
  const envLabel = isProd ? 'Production (push.interra.ru)' : 'Localhost';
  const baseUrl = config.serverBaseUrl;

  const msg =
    `🟢 <b>[INTERRA PUSH SERVER] Запущен</b>\n` +
    `----------------------------------\n` +
    `Сервер: <b>${envLabel}</b>\n` +
    `Порт: <code>${port}</code>\n\n` +
    `Админка: <a href="${baseUrl}/admin.html">${baseUrl}/admin.html</a>\n` +
    `Документация: <a href="${baseUrl}/docs">${baseUrl}/docs</a>\n` +
    `Метрики: <a href="${baseUrl}/metrics">${baseUrl}/metrics</a>\n` +
    `Здоровье: <a href="${baseUrl}/healthz">${baseUrl}/healthz</a>\n` +
    `----------------------------------`;

  const buttons: TelegramReplyMarkup = {
    inline_keyboard: [
      [
        { text: '🎛 Админка', url: `${baseUrl}/admin.html` },
        { text: '📚 Документация', url: `${baseUrl}/docs` },
      ],
      [
        { text: '📊 Метрики', url: `${baseUrl}/metrics` },
        { text: '🩺 Health', url: `${baseUrl}/healthz` },
      ],
    ],
  };

  sendTelegramAlert(msg, buttons);
}

/**
 * Шаблон сообщения при остановке сервера
 */
export function sendServerShutdownAlert(signal: string): void {
  const isProd = config.nodeEnv === 'production' || config.serverBaseUrl.includes('push.interra.ru');
  const envLabel = isProd ? 'Production' : 'Localhost';

  const msg =
    `🔴 <b>[INTERRA PUSH SERVER] Остановлен</b>\n` +
    `----------------------------------\n` +
    `Сервер: <b>${envLabel}</b>\n` +
    `Сигнал: <code>${signal}</code>\n` +
    `SQLite БД: закрыта\n` +
    `----------------------------------`;
  sendTelegramAlert(msg);
}

/**
 * Шаблон алерта при 500 критической ошибке
 */
export function sendServerErrorAlert(path: string, method: string, requestId: string, error: string): void {
  const baseUrl = config.serverBaseUrl;
  const fullUrl = `${baseUrl}${path}`;

  const msg =
    `💥 <b>[INTERRA SERVER ALERT] Ошибка 500</b>\n` +
    `----------------------------------\n` +
    `Маршрут: <code>${method}</code> <a href="${fullUrl}">${fullUrl}</a>\n` +
    `Request ID: <code>${requestId}</code>\n` +
    `Ошибка: <code>${error}</code>\n` +
    `----------------------------------`;
  sendTelegramAlert(msg);
}

/**
 * Простой обработчик команд Telegram бота (/push <текст>)
 */
let pollingInterval: NodeJS.Timeout | null = null;
let lastUpdateId = 0;

export function initTelegramBotCommands(): void {
  const { telegramBotToken } = config;
  if (!telegramBotToken) return;

  pollingInterval = setInterval(async () => {
    try {
      const res = await fetch(`https://api.telegram.org/bot${telegramBotToken}/getUpdates?offset=${lastUpdateId + 1}&limit=5&timeout=0`);
      if (!res.ok) return;

      const data = (await res.json()) as { ok: boolean; result: Array<{ update_id: number; message?: { text?: string; chat: { id: number } } }> };
      if (!data.ok || !data.result) return;

      for (const update of data.result) {
        lastUpdateId = update.update_id;
        const text = update.message?.text?.trim();
        const chatId = update.message?.chat.id;

        if (text && text.startsWith('/push ') && chatId) {
          const pushBody = text.replace('/push ', '').trim();
          if (!pushBody) continue;

          try {
            const result = await broadcastService.sendBroadcast({
              title: 'Сообщение от провайдера',
              body: pushBody,
              target: { type: 'all' },
            });

            await sendTelegramAlert(
              `✅ <b>Рассылка выполнена через Telegram!</b>\n` +
              `----------------------------------\n` +
              `Текст: <i>${pushBody}</i>\n` +
              `Отправлено: <b>${result.successCount}</b> устройств\n` +
              `----------------------------------`
            );
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка выполнения рассылки:</b> ${(err as Error).message}`);
          }
        }
      }
    } catch (err) {
      // Игнорируем сетевые сбои в фоновом поллинге
    }
  }, 10000);
}

export function stopTelegramBotCommands(): void {
  if (pollingInterval) {
    clearInterval(pollingInterval);
    pollingInterval = null;
  }
}
