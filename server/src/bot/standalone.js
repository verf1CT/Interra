// Запуск Telegram-бота в режиме Long Polling (для локальной разработки и автономного запуска)
import 'dotenv/config';
import { BotEngine } from './botEngine.js';
import { TelegramClient } from './telegramClient.js';
import { TelegramHandler } from './telegramHandler.js';

const token = process.env.TELEGRAM_BOT_TOKEN;

if (!token) {
  console.error('Ошибка: Переменная TELEGRAM_BOT_TOKEN не задана в .env файле.');
  console.log('Для тестирования без токена запустите симулятор:');
  console.log('   npm run bot:sim');
  process.exit(1);
}

const engine = new BotEngine();
const tgClient = new TelegramClient(token);
const tgHandler = new TelegramHandler(engine, tgClient);

console.log('Запуск Telegram-бота «Интерра»...');
tgHandler.startPolling().catch(err => {
  console.error('Фатальная ошибка бота:', err);
  process.exit(1);
});
