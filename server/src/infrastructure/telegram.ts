import { config } from '../config/env.js';
import { logger } from './logger.js';

/**
 * Отправляет сообщение в Telegram-чат администраторов.
 * Если TELEGRAM_BOT_TOKEN или TELEGRAM_CHAT_ID не заданы, вызов тихо игнорируется.
 */
export async function sendTelegramAlert(text: string): Promise<boolean> {
  const { telegramBotToken, telegramChatId } = config;

  if (!telegramBotToken || !telegramChatId) {
    return false;
  }

  try {
    const url = `https://api.telegram.org/bot${telegramBotToken}/sendMessage`;
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: telegramChatId,
        text,
        parse_mode: 'HTML',
        disable_web_page_preview: true,
      }),
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
 * Шаблон сообщения при запуске сервера
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
  sendTelegramAlert(msg);
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
