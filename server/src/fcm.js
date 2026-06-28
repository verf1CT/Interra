import fs from 'node:fs';
import admin from 'firebase-admin';
import { config } from './config.js';
import { deleteDevice } from './db.js';

let messaging = null;
let enabled = false;

if (config.firebaseServiceAccount && fs.existsSync(config.firebaseServiceAccount)) {
  const serviceAccount = JSON.parse(fs.readFileSync(config.firebaseServiceAccount, 'utf8'));
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  messaging = admin.messaging();
  enabled = true;
  console.log('[fcm] Firebase инициализирован — push включён.');
} else {
  console.warn(
    '[fcm] Ключ Firebase не найден (' +
      (config.firebaseServiceAccount || 'FIREBASE_SERVICE_ACCOUNT не задан') +
      '). Push отключён — сообщения будут только логироваться (dry-run).'
  );
}

export const fcmEnabled = () => enabled;

/**
 * Рассылает push на список токенов. Возвращает {successCount, failureCount}.
 * Невалидные/отписавшиеся токены автоматически удаляются из БД.
 */
export async function sendToTokens(tokens, { title, body, data }) {
  const unique = [...new Set(tokens)].filter(Boolean);
  if (unique.length === 0) return { successCount: 0, failureCount: 0 };

  // data-значения в FCM должны быть строками
  const stringData = Object.fromEntries(
    Object.entries(data ?? {}).map(([k, v]) => [k, String(v)])
  );

  if (!enabled) {
    console.log(
      `[fcm:dry-run] "${title}" → ${unique.length} устройств. body="${body}" data=${JSON.stringify(stringData)}`
    );
    return { successCount: unique.length, failureCount: 0 };
  }

  let successCount = 0;
  let failureCount = 0;

  // FCM ограничивает multicast 500 токенами за запрос
  for (let i = 0; i < unique.length; i += 500) {
    const batch = unique.slice(i, i + 500);
    const res = await messaging.sendEachForMulticast({
      tokens: batch,
      notification: { title, body },
      data: stringData,
      android: { priority: 'high', notification: { sound: 'default' } },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    successCount += res.successCount;
    failureCount += res.failureCount;

    res.responses.forEach((r, idx) => {
      if (!r.success) {
        const code = r.error?.code || '';
        if (
          code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token' ||
          code === 'messaging/invalid-argument'
        ) {
          deleteDevice(batch[idx]);
        }
      }
    });
  }

  return { successCount, failureCount };
}
