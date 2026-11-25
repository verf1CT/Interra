// Запуск бота платформы MAX (business.max.ru) в автономном режиме Long Polling
import 'dotenv/config';
import { BotEngine } from './botEngine.js';
import { MaxClient } from './maxClient.js';
import { MaxHandler } from './maxHandler.js';

const token = process.env.MAX_BOT_TOKEN;

if (!token) {
  console.error('Ошибка: Переменная MAX_BOT_TOKEN не задана в .env файле.');
  console.log('Получите токен на портале: https://business.max.ru/self/chat-bots');
  console.log('   Или запустите локальный симулятор: npm run bot:sim');
  process.exit(1);
}

const engine = new BotEngine();
const maxClient = new MaxClient(token);
const maxHandler = new MaxHandler(engine, maxClient);

console.log('Запуск бота «Интерра» на платформе MAX (platform-api2.max.ru)...');
maxHandler.startPolling().catch(err => {
  console.error('Фатальная ошибка MAX бота:', err);
  process.exit(1);
});
