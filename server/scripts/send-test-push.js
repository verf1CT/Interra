// Отправка тестового push НАПРЯМУЮ через Firebase Cloud Messaging,
// в обход бэкенда (нужен только serviceAccountKey.json этого проекта).
//
// Использование:
//   node scripts/send-test-push.js --token <FCM_TOKEN> "Заголовок" "Текст"
//   node scripts/send-test-push.js --topic all           "Заголовок" "Текст"
//
// Токен устройства берётся с телефона (см. README/инструкцию). Топик работает,
// только если приложение подписано на него (FirebaseMessaging.subscribeToTopic).

import admin from 'firebase-admin';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const args = process.argv.slice(2);
const kind = args[0]; // --token | --topic
const target = args[1];
const title = args[2] || 'Интерра';
const body = args[3] || 'Тестовое уведомление';

if ((kind !== '--token' && kind !== '--topic') || !target) {
  console.error('Использование: node scripts/send-test-push.js --token <TOKEN>|--topic <NAME> "Заголовок" "Текст"');
  process.exit(1);
}

const serviceAccount = JSON.parse(
  readFileSync(path.join(__dirname, '..', 'serviceAccountKey.json'), 'utf8'),
);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

// notification-сообщение: показывается и на переднем плане (приложение само
// рисует локальное уведомление), и в фоне (системный трей Android)
const message = {
  notification: { title, body },
  android: { priority: 'high' },
  ...(kind === '--token' ? { token: target } : { topic: target }),
};

admin.messaging().send(message)
  .then((id) => { console.log('✅ Отправлено, messageId:', id); process.exit(0); })
  .catch((e) => { console.error('❌ Ошибка отправки:', e.message); process.exit(1); });
