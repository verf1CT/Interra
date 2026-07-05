// Отправка тестового push НАПРЯМУЮ через Firebase Cloud Messaging,
// в обход бэкенда (нужен только serviceAccountKey.json этого проекта).
//
// Использование:
//   node scripts/send-test-push.js --token <FCM_TOKEN> "Заголовок" "Текст"
//   node scripts/send-test-push.js --topic all           "Заголовок" "Текст"
//
// Токен устройства берётся с телефона (см. README/инструкцию). Топик работает,
// только если приложение подписано на него (FirebaseMessaging.subscribeToTopic).

const admin = require('firebase-admin');
const path = require('path');

const args = process.argv.slice(2);
const kind = args[0]; // --token | --topic
const target = args[1];
const title = args[2] || 'Интерра';
const body = args[3] || 'Тестовое уведомление';

if ((kind !== '--token' && kind !== '--topic') || !target) {
  console.error('Использование: node scripts/send-test-push.js --token <TOKEN>|--topic <NAME> "Заголовок" "Текст"');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(path.join(__dirname, '..', 'serviceAccountKey.json'))),
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
