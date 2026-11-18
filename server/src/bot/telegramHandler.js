// Мост между Telegram Bot API и движком BotEngine

export class TelegramHandler {
  constructor(botEngine, telegramClient) {
    this.engine = botEngine;
    this.tg = telegramClient;
  }

  // Конвертация кнопок движка в формат Telegram inline_keyboard
  formatKeyboard(buttons) {
    if (!buttons || buttons.length === 0) return null;

    // Группируем длинные кнопки по одной в ряд, короткие по 2
    const keyboard = [];
    for (const btn of buttons) {
      if (btn.url) {
        keyboard.push([{ text: btn.text, url: btn.url }]);
      } else {
        const callbackData = JSON.stringify({
          n: btn.next,
          v: btn.value || undefined
        });
        keyboard.push([{ text: btn.text, callback_data: callbackData }]);
      }
    }
    return { inline_keyboard: keyboard };
  }

  // Обработка входящего обновления от Telegram (Webhook или Long Polling)
  async handleUpdate(update) {
    try {
      // 1. Нажатие на Inline-кнопку (callback_query)
      if (update.callback_query) {
        const query = update.callback_query;
        const chatId = query.message.chat.id;
        const messageId = query.message.message_id;
        const callbackQueryId = query.id;

        await this.tg.answerCallbackQuery(callbackQueryId);

        let data = {};
        try {
          data = JSON.parse(query.data);
        } catch {
          data = { n: query.data };
        }

        const nextStep = data.n;
        const value = data.v;

        const rendered = await this.engine.handleButtonClick(String(chatId), nextStep, value);
        await this.tg.sendMessage(chatId, rendered.text, this.formatKeyboard(rendered.buttons));

        // Если шаг с автопереходом (например, удаленный сброс порта коммутатора)
        if (rendered.isAutoTransition && rendered.next) {
          setTimeout(async () => {
            const nextRendered = await this.engine.transitionTo(this.engine.getSession(String(chatId)), rendered.next);
            await this.tg.sendMessage(chatId, nextRendered.text, this.formatKeyboard(nextRendered.buttons));
          }, 4000);
        }

        return;
      }

      // 2. Обычное текстовое сообщение
      if (update.message && update.message.text) {
        const chatId = update.message.chat.id;
        const text = update.message.text.trim();

        if (text === '/start') {
          const rendered = await this.engine.handleStart(String(chatId));
          await this.tg.sendMessage(chatId, rendered.text, this.formatKeyboard(rendered.buttons));
          return;
        }

        const rendered = await this.engine.handleTextInput(String(chatId), text);
        await this.tg.sendMessage(chatId, rendered.text, this.formatKeyboard(rendered.buttons));

        if (rendered.isAutoTransition && rendered.next) {
          setTimeout(async () => {
            const nextRendered = await this.engine.transitionTo(this.engine.getSession(String(chatId)), rendered.next);
            await this.tg.sendMessage(chatId, nextRendered.text, this.formatKeyboard(nextRendered.buttons));
          }, 4000);
        }
      }
    } catch (err) {
      console.error('[TelegramHandler Error]', err);
    }
  }

  // Запуск Long Polling для локального запуска без webhook
  async startPolling() {
    console.log('[TelegramBot] Запущен режим Long Polling...');
    let offset = 0;
    while (true) {
      try {
        const updates = await this.tg.getUpdates(offset, 25);
        if (updates.ok && updates.result) {
          for (const u of updates.result) {
            offset = u.update_id + 1;
            await this.handleUpdate(u);
          }
        }
      } catch (err) {
        console.error('[Polling Error]', err.message);
        await new Promise(r => setTimeout(r, 5000));
      }
    }
  }
}
