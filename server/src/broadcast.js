import { selectTokens, logBroadcast, updateBroadcastResult } from './db.js';
import { sendToTokens } from './fcm.js';

/**
 * выполняет рассылку: выбирает токены по цели, журналирует (получая id для
 * трекинга открытий), шлёт в FCM и проставляет счётчики доставки.
 * Общая логика для немедленной отправки (routes/admin) и планировщика (scheduler).
 * @returns {{recipients, successCount, failureCount, note?}}
 */
export async function runBroadcast({ title, body, target, data, imageUrl, link }) {
  const tokens = selectTokens(target);
  if (tokens.length === 0) {
    return { recipients: 0, successCount: 0, failureCount: 0, note: 'нет получателей' };
  }

  // link уходит в data, чтобы приложение открыло его по тапу
  const outData = { ...(data || {}), ...(link ? { link } : {}) };

  // журналируем ДО отправки — нужен id, чтобы приложение вернуло его при
  // открытии (open-rate). Счётчики доставки проставим после отправки
  const logged = logBroadcast({
    title,
    body,
    data: { ...outData, ...(imageUrl ? { image: imageUrl } : {}) },
    target,
    recipients: tokens.length,
    successCount: 0,
    failureCount: 0,
  });
  const bid = logged.lastInsertRowid;
  outData.bid = bid;

  const { successCount, failureCount } = await sendToTokens(tokens, {
    title,
    body,
    data: outData,
    imageUrl: imageUrl || undefined,
  });

  updateBroadcastResult(bid, successCount, failureCount);
  return { recipients: tokens.length, successCount, failureCount };
}
