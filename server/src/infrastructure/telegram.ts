import fs from 'node:fs';
import { config } from '../config/env.js';
import { logger } from './logger.js';
import { broadcastService } from '../services/broadcast.service.js';
import { DeviceRepository, DeviceRow } from '../repositories/device.repository.js';

const deviceRepo = new DeviceRepository();

export interface TelegramInlineButton {
  text: string;
  url?: string;
  callback_data?: string;
}

export interface TelegramReplyMarkup {
  inline_keyboard?: TelegramInlineButton[][];
}

/**
 * Отправляет текстовое сообщение в Telegram-чат администраторов.
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
 * Отправляет файл (документ) в Telegram-чат администраторов.
 */
export async function sendTelegramDocument(filename: string, fileBuffer: Buffer, caption?: string): Promise<boolean> {
  const { telegramBotToken, telegramChatId } = config;

  if (!telegramBotToken || !telegramChatId) {
    return false;
  }

  try {
    const formData = new FormData();
    formData.append('chat_id', telegramChatId);
    formData.append('document', new Blob([new Uint8Array(fileBuffer)]), filename);
    if (caption) {
      formData.append('caption', caption);
    }

    const response = await fetch(`https://api.telegram.org/bot${telegramBotToken}/sendDocument`, {
      method: 'POST',
      body: formData,
    });

    if (!response.ok) {
      const errText = await response.text();
      logger.error({ errText, status: response.status }, 'Ошибка отправки документа в Telegram');
      return false;
    }

    return true;
  } catch (err) {
    logger.error({ err }, 'Ошибка сети при отправке документа в Telegram');
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
 * Обработчик команд Telegram бота (/push, /stats, /backup, /help)
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

        if (!text || !chatId) continue;

        const cmd = text.split(' ')[0].toLowerCase();

        // 1. /push <текст>
        if (cmd === '/push' || cmd.startsWith('/push@')) {
          const pushBody = text.replace(/^\/push(@\w+)?\s*/i, '').trim();
          if (!pushBody) {
            await sendTelegramAlert('⚠️ Укажите текст рассылки. Пример: <code>/push Скоро технические работы.</code>');
            continue;
          }

          try {
            const result = await broadcastService.runBroadcast({
              title: 'Сообщение от провайдера',
              body: pushBody,
              target: { type: 'all' },
            });

            await sendTelegramAlert(
              `✅ <b>Рассылка выполнена через Telegram!</b>\n` +
              `----------------------------------\n` +
              `Текст: <i>${pushBody}</i>\n` +
              `Успешно отправлено: <b>${result.successCount}</b>\n` +
              `Ошибок: <b>${result.failureCount}</b>\n` +
              `----------------------------------`
            );
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка выполнения рассылки:</b> ${(err as Error).message}`);
          }
        }

        // 2. /stats
        else if (cmd === '/stats' || cmd.startsWith('/stats@')) {
          try {
            const devices = deviceRepo.listAll();
            const iosCount = devices.filter((d: DeviceRow) => d.platform === 'ios').length;
            const androidCount = devices.filter((d: DeviceRow) => d.platform === 'android').length;
            const webCount = devices.filter((d: DeviceRow) => d.platform === 'web' || !d.platform).length;

            const uptimeSec = Math.floor(process.uptime());
            const hours = Math.floor(uptimeSec / 3600);
            const minutes = Math.floor((uptimeSec % 3600) / 60);

            const memMb = (process.memoryUsage().rss / (1024 * 1024)).toFixed(1);
            let dbSizeMb = '0';
            if (fs.existsSync(config.dbPath)) {
              dbSizeMb = (fs.statSync(config.dbPath).size / (1024 * 1024)).toFixed(2);
            }

            const msg =
              `📊 <b>[INTERRA SERVER STATS]</b>\n` +
              `----------------------------------\n` +
              `📱 <b>Всего устройств</b>: <b>${devices.length}</b>\n` +
              `  ├ 🍏 iOS: <b>${iosCount}</b>\n` +
              `  ├ 🤖 Android: <b>${androidCount}</b>\n` +
              `  └ 🌐 Web / Прочие: <b>${webCount}</b>\n\n` +
              `⏱ <b>Uptime</b>: ${hours}ч ${minutes}мин\n` +
              `🧠 <b>RAM RSS</b>: <code>${memMb} MB</code>\n` +
              `💾 <b>SQLite БД</b>: <code>${dbSizeMb} MB</code>\n` +
              `----------------------------------`;
            await sendTelegramAlert(msg);
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка получения статистики:</b> ${(err as Error).message}`);
          }
        }

        // 3. /backup
        else if (cmd === '/backup' || cmd.startsWith('/backup@')) {
          try {
            if (fs.existsSync(config.dbPath)) {
              const fileBuf = fs.readFileSync(config.dbPath);
              const dateStr = new Date().toISOString().slice(0, 10);
              const filename = `interra-backup-${dateStr}.sqlite`;

              const ok = await sendTelegramDocument(
                filename,
                fileBuf,
                `💾 Резервная копия БД SQLite (${(fileBuf.length / (1024 * 1024)).toFixed(2)} MB)`
              );
              if (!ok) {
                await sendTelegramAlert('❌ Ошибка отправки резервной копии базы данных.');
              }
            } else {
              await sendTelegramAlert('⚠️ Файл базы данных не найден.');
            }
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка создания бэкапа:</b> ${(err as Error).message}`);
          }
        }

        // 4. /help или /start
        else if (cmd === '/help' || cmd.startsWith('/help@') || cmd === '/start' || cmd.startsWith('/start@')) {
          const msg =
            `🤖 <b>[INTERRA BOT COMMANDS]</b>\n` +
            `----------------------------------\n` +
            `• <code>/push &lt;текст&gt;</code> — отправить рассылку всем абонентам\n` +
            `• <code>/stats</code> — статистика устройств, памяти и uptime\n` +
            `• <code>/backup</code> — скачать файл базы данных SQLite\n` +
            `• <code>/help</code> — список команд\n` +
            `----------------------------------`;
          await sendTelegramAlert(msg);
        }
      }
    } catch (err) {
      // Игнорируем фоновые сетевые ошибки поллинга
    }
  }, 5000);
}

export function stopTelegramBotCommands(): void {
  if (pollingInterval) {
    clearInterval(pollingInterval);
    pollingInterval = null;
  }
}
