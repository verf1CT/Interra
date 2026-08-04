import fs from 'node:fs';
import { performance } from 'node:perf_hooks';
import fetch, { RequestInit, Response } from 'node-fetch';
import { HttpsProxyAgent } from 'https-proxy-agent';
import { SocksProxyAgent } from 'socks-proxy-agent';
import { config } from '../config/env.js';
import { logger } from './logger.js';
import { broadcastService } from '../services/broadcast.service.js';
import { DeviceRepository, DeviceRow } from '../repositories/device.repository.js';
import { db } from '../db/connection.js';
import { incidentService } from '../services/incident.service.js';

function escapeHtml(text: string) { return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

function createProxyAgent(proxyUrl?: string) {
  if (!proxyUrl) return undefined;
  if (proxyUrl.startsWith('socks')) {
    return new SocksProxyAgent(proxyUrl);
  }
  return new HttpsProxyAgent(proxyUrl);
}

const proxyAgent = createProxyAgent(config.telegramProxy);

function telegramFetch(url: string, init?: RequestInit): Promise<Response> {
  return fetch(url, {
    ...init,
    ...(proxyAgent ? { agent: proxyAgent } : {}),
  } as any);
}

const deviceRepo = new DeviceRepository();

export interface TelegramInlineButton {
  text: string;
  url?: string;
  callback_data?: string;
}

export interface TelegramKeyboardButton {
  text: string;
}

export interface TelegramReplyMarkup {
  inline_keyboard?: TelegramInlineButton[][];
  keyboard?: TelegramKeyboardButton[][];
  resize_keyboard?: boolean;
}

export const defaultReplyKeyboard: TelegramReplyMarkup = {
  keyboard: [
    [{ text: '🧙‍♂️ Пошаговая рассылка' }],
    [{ text: '📊 Статистика' }, { text: '💾 Бэкап БД' }],
    [{ text: '🚨 Аварии' }, { text: '🏓 Пинг' }, { text: '❓ Справка' }],
  ],
  resize_keyboard: true,
};

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

    const response = await telegramFetch(url, {
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

    const response = await telegramFetch(`https://api.telegram.org/bot${telegramBotToken}/sendDocument`, {
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
 * Автоматически регистрирует список команд (/...) в Telegram API.
 */
export async function registerTelegramBotMenu(): Promise<void> {
  const { telegramBotToken } = config;
  if (!telegramBotToken) return;

  try {
    const url = `https://api.telegram.org/bot${telegramBotToken}/setMyCommands`;
    const commands = [
      { command: 'wizard', description: '🧙‍♂️ Пошаговый мастер создания рассылки' },
      { command: 'push', description: 'Массовая рассылка всем абонентам' },
      { command: 'send', description: 'Персональный push: /send <логин> <текст>' },
      { command: 'find', description: 'Поиск устройства: /find <логин>' },
      { command: 'incident', description: '🚨 Создать аварию: /incident <описание>' },
      { command: 'planned', description: '🔧 Плановые работы: /planned <описание>' },
      { command: 'resolve', description: '✅ Закрыть инцидент: /resolve <id>' },
      { command: 'incidents', description: '📋 Список активных инцидентов' },
      { command: 'stats', description: 'Статистика устройств, памяти и uptime' },
      { command: 'backup', description: 'Скачать бэкап базы данных SQLite' },
      { command: 'ping', description: 'Проверить отклик сервера и БД' },
      { command: 'help', description: 'Справка по всем командам' },
    ];

    await telegramFetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ commands }),
    });
  } catch (err) {
    logger.error({ err }, 'Ошибка при регистрации меню команд Telegram бота');
  }
}

interface WizardSession {
  step: 'title' | 'body' | 'screen' | 'confirm';
  title?: string;
  body?: string;
  screen?: string;
  updatedAt: number;
}

const wizardSessions = new Map<number, WizardSession>();

async function answerCallbackQuery(callbackQueryId: string): Promise<void> {
  const { telegramBotToken } = config;
  if (!telegramBotToken) return;
  try {
    await telegramFetch(`https://api.telegram.org/bot${telegramBotToken}/answerCallbackQuery`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ callback_query_id: callbackQueryId }),
    });
  } catch (_) {}
}

async function editTelegramAlert(chatId: number, messageId: number, text: string, replyMarkup?: TelegramReplyMarkup): Promise<void> {
  const { telegramBotToken } = config;
  if (!telegramBotToken) return;
  try {
    await telegramFetch(`https://api.telegram.org/bot${telegramBotToken}/editMessageText`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        message_id: messageId,
        text,
        parse_mode: 'HTML',
        reply_markup: replyMarkup,
      }),
    });
  } catch (_) {}
}

/**
 * Обработчик команд Telegram бота (/push, /wizard, /send, /find, /stats, /backup, /ping, /help)
 */
let pollingInterval: NodeJS.Timeout | null = null;
let lastUpdateId = 0;

export function initTelegramBotCommands(): void {
  const { telegramBotToken } = config;
  if (!telegramBotToken) return;

  registerTelegramBotMenu();

  setInterval(() => {
    const now = Date.now();
    for (const [chatId, session] of wizardSessions.entries()) {
      if (now - session.updatedAt > 600000) {
        wizardSessions.delete(chatId);
      }
    }
  }, 5 * 60 * 1000);

  pollingInterval = setInterval(async () => {
    try {
      const res = await telegramFetch(`https://api.telegram.org/bot${telegramBotToken}/getUpdates?offset=${lastUpdateId + 1}&limit=5&timeout=0`);
      if (!res.ok) return;

      const data = (await res.json()) as {
        ok: boolean;
        result: Array<{
          update_id: number;
          message?: { text?: string; chat: { id: number } };
          callback_query?: { id: string; data: string; message?: { message_id: number; chat: { id: number } } };
        }>;
      };
      if (!data.ok || !data.result) return;

      for (const update of data.result) {
        lastUpdateId = update.update_id;

        // --- Обработка нажатий на инлайн-кнопки (callback_query) ---
        if (update.callback_query) {
          const cb = update.callback_query;
          const chatId = cb.message?.chat.id;
          const msgId = cb.message?.message_id;
          if (!chatId || !msgId) continue;

          const allowedChatId = Number(config.telegramChatId);
          if (allowedChatId && chatId !== allowedChatId) continue;

          await answerCallbackQuery(cb.id);

          const session = wizardSessions.get(chatId);

          if (cb.data.startsWith('wiz_scr_')) {
            if (!session) continue;
            const screenType = cb.data.replace('wiz_scr_', '');
            session.screen = screenType === 'none' ? undefined : screenType;
            session.step = 'confirm';
            session.updatedAt = Date.now();

            const screenLabel = session.screen ? `<code>${session.screen}</code>` : 'отсутствует';
            const previewMsg =
              `📋 <b>Предпросмотр рассылки:</b>\n` +
              `----------------------------------\n` +
              `Заголовок: <b>${escapeHtml(session.title || '')}</b>\n` +
              `Текст: <i>${escapeHtml(session.body || '')}</i>\n` +
              `Deep link: ${screenLabel}\n` +
              `----------------------------------\n\n` +
              `Отправить эту рассылку всем абонентам?`;

            await editTelegramAlert(chatId, msgId, previewMsg, {
              inline_keyboard: [
                [
                  { text: '🚀 Отправить всем', callback_data: 'wiz_send' },
                  { text: '❌ Отмена', callback_data: 'wiz_cancel' },
                ],
              ],
            });
          } else if (cb.data === 'wiz_send') {
            if (!session || !session.title || !session.body) {
              await editTelegramAlert(chatId, msgId, '⚠️ Сессия создания рассылки истекла. Запустите /wizard снова.');
              continue;
            }

            try {
              const result = await broadcastService.runBroadcast({
                title: session.title,
                body: session.body,
                target: { type: 'all' },
                screen: session.screen,
              });

              const screenText = session.screen ? `\nDeep link: <code>${session.screen}</code>` : '';
              await editTelegramAlert(
                chatId,
                msgId,
                `✅ <b>Массовая рассылка успешно выполнена!</b>\n` +
                `----------------------------------\n` +
                `Заголовок: <b>${escapeHtml(session.title || '')}</b>\n` +
                `Текст: <i>${escapeHtml(session.body || '')}</i>${screenText}\n` +
                `Успешно отправлено: <b>${result.successCount}</b>\n` +
                `Ошибок: <b>${result.failureCount}</b>\n` +
                `----------------------------------`
              );
            } catch (err) {
              await editTelegramAlert(chatId, msgId, `❌ <b>Ошибка рассылки:</b> ${(err as Error).message}`);
            }
            wizardSessions.delete(chatId);
          } else if (cb.data === 'wiz_cancel') {
            wizardSessions.delete(chatId);
            await editTelegramAlert(chatId, msgId, '❌ Создание рассылки отменено.');
          }

          continue;
        }

        // --- Обработка текстовых сообщений ---
        const text = update.message?.text?.trim();
        const chatId = update.message?.chat.id;

        if (!text || !chatId) continue;

        // Проверка авторизации: принимаем команды только из админской группы
        const allowedChatId = Number(config.telegramChatId);
        if (allowedChatId && chatId !== allowedChatId) {
          try {
            await telegramFetch(`https://api.telegram.org/bot${telegramBotToken}/sendMessage`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                chat_id: chatId,
                text: '⛔️ Доступ запрещён. Бот принимает команды только из авторизованной группы.',
              }),
            });
          } catch (_) {}
          continue;
        }

        const cmd = text.split(' ')[0].toLowerCase();

        // Команда /cancel для отмены визарда
        if (cmd === '/cancel' || cmd.startsWith('/cancel@')) {
          if (wizardSessions.has(chatId)) {
            wizardSessions.delete(chatId);
            await sendTelegramAlert('❌ Создание рассылки отменено.', defaultReplyKeyboard);
          } else {
            await sendTelegramAlert('ℹ️ У вас нет активных сессий создания рассылки.', defaultReplyKeyboard);
          }
          continue;
        }

        // Обработка активных шагов Wizard (если не команда)
        const session = wizardSessions.get(chatId);
        if (session && !text.startsWith('/')) {
          if (session.step === 'title') {
            session.title = text === '-' ? 'Сообщение от провайдера' : text;
            session.step = 'body';
            session.updatedAt = Date.now();
            await sendTelegramAlert(
              `🧙‍♂️ <b>Мастер создания рассылки (Шаг 2 из 3)</b>\n\n` +
              `Заголовок: <b>${escapeHtml(session.title || '')}</b>\n\n` +
              `Теперь введите <b>текст сообщения</b>:\n\n` +
              `<i>Для отмены отправьте /cancel</i>`,
              defaultReplyKeyboard
            );
            continue;
          } else if (session.step === 'body') {
            session.body = text;
            session.step = 'screen';
            session.updatedAt = Date.now();
            await sendTelegramAlert(
              `🧙‍♂️ <b>Мастер создания рассылки (Шаг 3 из 3)</b>\n\n` +
              `Заголовок: <b>${escapeHtml(session.title || '')}</b>\n` +
              `Текст: <i>${escapeHtml(session.body || '')}</i>\n\n` +
              `Выберите <b>экран приложения (Deep Link)</b> при тапе по push:`,
              {
                inline_keyboard: [
                  [{ text: '🚫 Без перехода', callback_data: 'wiz_scr_none' }],
                  [{ text: '📊 Диагностика', callback_data: 'wiz_scr_diagnostics' }, { text: '⚙️ Настройки', callback_data: 'wiz_scr_settings' }],
                  [{ text: '💬 Поддержка', callback_data: 'wiz_scr_support' }, { text: '💳 Оплата', callback_data: 'wiz_scr_payment' }],
                  [{ text: '🔔 Уведомления', callback_data: 'wiz_scr_notifications' }],
                ],
              }
            );
            continue;
          }
        }

        // --- Команды ---

        // 0. /wizard или кнопка "🧙‍♂️ Пошаговая рассылка"
        if (cmd === '/wizard' || cmd.startsWith('/wizard@') || text === '🧙‍♂️ Пошаговая рассылка') {
          wizardSessions.set(chatId, { step: 'title', updatedAt: Date.now() });
          await sendTelegramAlert(
            `🧙‍♂️ <b>Мастер создания рассылки (Шаг 1 из 3)</b>\n\n` +
            `Введите <b>заголовок</b> уведомления (или отправьте <code>-</code> для заглавия «Сообщение от провайдера»):\n\n` +
            `<i>Для отмены отправьте /cancel</i>`,
            defaultReplyKeyboard
          );
          continue;
        }

        // 1. /push [--screen=diagnostics] <текст> (Массовая рассылка всем)
        if (cmd === '/push' || cmd.startsWith('/push@')) {
          let pushBody = text.replace(/^\/push(@\w+)?\s*/i, '').trim();
          if (!pushBody) {
            await sendTelegramAlert('⚠️ Укажите текст рассылки. Пример: <code>/push Скоро технические работы.</code>\nС deep link: <code>/push --screen=diagnostics Проверьте соединение!</code>', defaultReplyKeyboard);
            continue;
          }

          // парсим флаг --screen=xxx
          let screen: string | undefined;
          const screenMatch = pushBody.match(/--screen=(\w+)/);
          if (screenMatch) {
            screen = screenMatch[1];
            pushBody = pushBody.replace(/--screen=\w+\s*/g, '').trim();
          }

          try {
            const result = await broadcastService.runBroadcast({
              title: 'Сообщение от провайдера',
              body: pushBody,
              target: { type: 'all' },
              screen,
            });

            const screenLabel = screen ? `\nDeep link: <code>${screen}</code>` : '';
            await sendTelegramAlert(
              `✅ <b>Массовая рассылка выполнена!</b>\n` +
              `----------------------------------\n` +
              `Текст: <i>${pushBody}</i>${screenLabel}\n` +
              `Успешно отправлено: <b>${result.successCount}</b>\n` +
              `Ошибок: <b>${result.failureCount}</b>\n` +
              `----------------------------------`,
              defaultReplyKeyboard
            );
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка выполнения рассылки:</b> ${(err as Error).message}`, defaultReplyKeyboard);
          }
        }

        // 2. /send <телефон/логин> <текст> (Персональный Push)
        else if (cmd === '/send' || cmd.startsWith('/send@')) {
          const content = text.replace(/^\/send(@\w+)?\s*/i, '').trim();
          const firstSpaceIndex = content.indexOf(' ');

          if (firstSpaceIndex === -1) {
            await sendTelegramAlert(
              '⚠️ Укажите телефон и текст. Пример:\n<code>/send 79221112233 Баланс пополнен!</code>',
              defaultReplyKeyboard
            );
            continue;
          }

          const targetLogin = content.slice(0, firstSpaceIndex).trim();
          const pushBody = content.slice(firstSpaceIndex + 1).trim();

          if (!targetLogin || !pushBody) {
            await sendTelegramAlert('⚠️ Неверный формат. Пример: <code>/send 79221112233 Текст push</code>', defaultReplyKeyboard);
            continue;
          }

          try {
            const result = await broadcastService.runBroadcast({
              title: 'Сообщение от провайдера',
              body: pushBody,
              target: { type: 'login', value: targetLogin },
            });

            await sendTelegramAlert(
              `🎯 <b>Персональный push отправлен!</b>\n` +
              `----------------------------------\n` +
              `Получатель: <code>${targetLogin}</code>\n` +
              `Текст: <i>${pushBody}</i>\n` +
              `Успешно отправлено: <b>${result.successCount}</b>\n` +
              `----------------------------------`,
              defaultReplyKeyboard
            );
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка отправки персонального push:</b> ${(err as Error).message}`, defaultReplyKeyboard);
          }
        }

        // 3. /find <телефон/логин> (Поиск абонента/устройства)
        else if (cmd === '/find' || cmd.startsWith('/find@')) {
          const target = text.replace(/^\/find(@\w+)?\s*/i, '').trim();
          if (!target) {
            await sendTelegramAlert('⚠️ Укажите логин или телефон для поиска. Пример: <code>/find 79221112233</code>', defaultReplyKeyboard);
            continue;
          }

          try {
            const devices = deviceRepo.listAll();
            const matched = devices.filter(
              (d: DeviceRow) =>
                (d.client_login && d.client_login.includes(target)) ||
                d.token.includes(target)
            );

            if (matched.length === 0) {
              await sendTelegramAlert(`⚠️ Устройство с логином или токеном <code>${target}</code> не найдено.`, defaultReplyKeyboard);
            } else {
              let resMsg = `🔍 <b>Найдено устройств: ${matched.length}</b>\n----------------------------------\n`;
              for (const d of matched.slice(0, 3)) {
                resMsg +=
                  `👤 <b>Логин</b>: <code>${d.client_login || 'Без логина'}</code>\n` +
                  `📱 <b>Платформа</b>: <code>${d.platform || 'Не указана'}</code>\n` +
                  `📦 <b>Версия</b>: <code>${d.app_version || '1.0.0'}</code>\n` +
                  `📅 <b>Регистрация</b>: <code>${d.created_at}</code>\n` +
                  `🔑 <b>Токен</b>: <code>${d.token.slice(0, 18)}...</code>\n` +
                  `----------------------------------\n`;
              }
              await sendTelegramAlert(resMsg, defaultReplyKeyboard);
            }
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка поиска:</b> ${(err as Error).message}`, defaultReplyKeyboard);
          }
        }

        // 4. /stats или кнопка "📊 Статистика"
        else if (cmd === '/stats' || cmd.startsWith('/stats@') || text === '📊 Статистика') {
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
            await sendTelegramAlert(msg, defaultReplyKeyboard);
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка получения статистики:</b> ${(err as Error).message}`, defaultReplyKeyboard);
          }
        }

        // 5. /backup или кнопка "💾 Бэкап БД"
        else if (cmd === '/backup' || cmd.startsWith('/backup@') || text === '💾 Бэкап БД') {
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
                await sendTelegramAlert('❌ Ошибка отправки резервной копии базы данных.', defaultReplyKeyboard);
              }
            } else {
              await sendTelegramAlert('⚠️ Файл базы данных не найден.', defaultReplyKeyboard);
            }
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка создания бэкапа:</b> ${(err as Error).message}`, defaultReplyKeyboard);
          }
        }

        // 6. /ping или кнопка "🏓 Пинг"
        else if (cmd === '/ping' || cmd.startsWith('/ping@') || text === '🏓 Пинг') {
          try {
            const start = performance.now();
            db.prepare('SELECT 1').get();
            const dbMs = (performance.now() - start).toFixed(2);

            const uptimeSec = Math.floor(process.uptime());
            const hours = Math.floor(uptimeSec / 3600);
            const minutes = Math.floor((uptimeSec % 3600) / 60);

            const msg =
              `🏓 <b>[PONG] Сервер работает штатно</b>\n` +
              `----------------------------------\n` +
              `⚡️ <b>Отклик SQLite</b>: <code>${dbMs} ms</code>\n` +
              `⏱ <b>Uptime</b>: <code>${hours}ч ${minutes}мин</code>\n` +
              `🧠 <b>RAM RSS</b>: <code>${(process.memoryUsage().rss / (1024 * 1024)).toFixed(1)} MB</code>\n` +
              `----------------------------------`;
            await sendTelegramAlert(msg, defaultReplyKeyboard);
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка при выполнении пинга:</b> ${(err as Error).message}`, defaultReplyKeyboard);
          }
        }

        // /incident <описание> — создать аварию
        else if (cmd === '/incident' || cmd.startsWith('/incident@')) {
          const title = text.replace(/^\/incident(@\w+)?\s*/i, '').trim();
          if (!title) {
            await sendTelegramAlert('⚠️ Укажите описание аварии. Пример: <code>/incident Обрыв оптики на ул. Ленина</code>', defaultReplyKeyboard);
            continue;
          }
          try {
            const incident = await incidentService.createIncident({ title, type: 'incident' });
            // Alert is already sent by incidentService
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка создания инцидента:</b> ${(err as Error).message}`, defaultReplyKeyboard);
          }
        }

        // /planned <описание> — создать плановые работы
        else if (cmd === '/planned' || cmd.startsWith('/planned@')) {
          const title = text.replace(/^\/planned(@\w+)?\s*/i, '').trim();
          if (!title) {
            await sendTelegramAlert('⚠️ Укажите описание работ. Пример: <code>/planned Техработы 06.08 02:00-06:00</code>', defaultReplyKeyboard);
            continue;
          }
          try {
            const incident = await incidentService.createIncident({ title, type: 'planned_work' });
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка создания плановых работ:</b> ${(err as Error).message}`, defaultReplyKeyboard);
          }
        }

        // /resolve <id> — закрыть инцидент
        else if (cmd === '/resolve' || cmd.startsWith('/resolve@')) {
          const idStr = text.replace(/^\/resolve(@\w+)?\s*/i, '').trim();
          const id = Number(idStr);
          if (!id || Number.isNaN(id)) {
            await sendTelegramAlert('⚠️ Укажите ID инцидента. Пример: <code>/resolve 3</code>', defaultReplyKeyboard);
            continue;
          }
          try {
            const resolved = await incidentService.resolveIncident(id);
            if (!resolved) {
              await sendTelegramAlert(`⚠️ Инцидент #${id} не найден или уже закрыт.`, defaultReplyKeyboard);
            }
            // Success alert is sent by incidentService
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка закрытия инцидента:</b> ${(err as Error).message}`, defaultReplyKeyboard);
          }
        }

        // /incidents или кнопка "🚨 Аварии" — список активных инцидентов
        else if (cmd === '/incidents' || cmd.startsWith('/incidents@') || text === '🚨 Аварии') {
          try {
            const active = incidentService.listActive();
            if (active.length === 0) {
              await sendTelegramAlert('✅ <b>Активных инцидентов нет.</b> Все системы работают штатно.', defaultReplyKeyboard);
            } else {
              let msg = `📋 <b>Активные инциденты (${active.length}):</b>\n----------------------------------\n`;
              for (const inc of active) {
                const emoji = inc.type === 'planned_work' ? '🔧' : '🚨';
                const area = inc.affected_area ? ` (${inc.affected_area})` : '';
                msg += `${emoji} <b>#${inc.id}</b> ${inc.title}${area}\n📅 ${inc.created_at}\n\n`;
              }
              msg += `Закрыть: <code>/resolve &lt;id&gt;</code>`;
              await sendTelegramAlert(msg, defaultReplyKeyboard);
            }
          } catch (err) {
            await sendTelegramAlert(`❌ <b>Ошибка получения инцидентов:</b> ${(err as Error).message}`, defaultReplyKeyboard);
          }
        }

        // 7. /help или /start или кнопка "❓ Справка"
        else if (
          cmd === '/help' ||
          cmd.startsWith('/help@') ||
          cmd === '/start' ||
          cmd.startsWith('/start@') ||
          text === '❓ Справка'
        ) {
          const msg =
            `🤖 <b>[INTERRA BOT COMMANDS]</b>\n` +
            `----------------------------------\n` +
            `• <code>/wizard</code> — пошаговый мастер создания рассылки\n` +
            `• <code>/push &lt;текст&gt;</code> — быстрая рассылка всем клиентам\n` +
            `• <code>/send &lt;логин&gt; &lt;текст&gt;</code> — персональный push клиенту\n` +
            `• <code>/find &lt;логин/телефон&gt;</code> — поиск устройства в базе\n` +
            `• <code>/incident &lt;текст&gt;</code> — создать аварию\n` +
            `• <code>/planned &lt;текст&gt;</code> — создать плановые работы\n` +
            `• <code>/resolve &lt;id&gt;</code> — закрыть инцидент\n` +
            `• <code>/incidents</code> — список активных инцидентов\n` +
            `• <code>/stats</code> — статистика устройств, памяти и uptime\n` +
            `• <code>/backup</code> — скачать файл базы данных SQLite\n` +
            `• <code>/ping</code> — проверка отклика сервера и базы данных\n` +
            `----------------------------------`;
          await sendTelegramAlert(msg, defaultReplyKeyboard);
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
