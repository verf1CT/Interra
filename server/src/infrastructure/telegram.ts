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
  const msg =
    `🟢 <b>[INTERRA PUSH SERVER] Запущен</b>\n` +
    `----------------------------------\n` +
    `📡 <b>PORT</b>        : <code>${port}</code>\n` +
    `🌍 <b>ENV</b>         : <code>${env}</code>\n` +
    `📊 <b>Metrics</b>     : <code>/metrics</code>\n` +
    `📚 <b>Scalar UI</b>   : <code>/docs</code>\n` +
    `⏱ <b>Время</b>       : <code>${new Date().toISOString()}</code>\n` +
    `----------------------------------`;
  sendTelegramAlert(msg);
}

/**
 * Шаблон сообщения при остановке сервера
 */
export function sendServerShutdownAlert(signal: string): void {
  const msg =
    `🔴 <b>[INTERRA PUSH SERVER] Остановлен</b>\n` +
    `----------------------------------\n` +
    `⚠️ <b>Сигнал</b>      : <code>${signal}</code>\n` +
    `💾 <b>SQLite БД</b>   : Соединение закрыто\n` +
    `----------------------------------`;
  sendTelegramAlert(msg);
}

/**
 * Шаблон алерта при 500 критической ошибке
 */
export function sendServerErrorAlert(path: string, method: string, requestId: string, error: string): void {
  const msg =
    `💥 <b>[INTERRA SERVER ALERT] Ошибка 500!</b>\n` +
    `----------------------------------\n` +
    `📍 <b>Маршрут</b>    : <code>${method} ${path}</code>\n` +
    `🆔 <b>Request ID</b>  : <code>${requestId}</code>\n` +
    `❌ <b>Текст</b>       : <code>${error}</code>\n` +
    `----------------------------------`;
  sendTelegramAlert(msg);
}
