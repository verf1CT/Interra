// Обработчик событий платформы MAX (platform-api2.max.ru)

export class MaxHandler {
  constructor(botEngine, maxClient) {
    this.engine = botEngine;
    this.max = maxClient;
  }

  // Обработка одного входящего события от MAX (через Webhook или Polling)
  async handleUpdate(update) {
    try {
      const type = update.update_type;

      // 1. Пользователь запустил бота (bot_started)
      if (type === 'bot_started') {
        const userId = String(update.user ? update.user.user_id : update.chat_id);
        const recipient = update.user?.user_id ? { userId } : { chatId: update.chat_id };

        const rendered = await this.engine.handleStart(userId);
        await this.max.sendMessage(recipient, rendered.text, rendered.buttons);
        return;
      }

      // 2. Нажатие на кнопку (message_callback)
      if (type === 'message_callback' && update.callback) {
        const cb = update.callback;
        const callbackId = cb.callback_id;
        const userId = String(cb.user ? cb.user.user_id : 'unknown');

        let data = {};
        try {
          data = JSON.parse(cb.payload);
        } catch {
          data = { n: cb.payload };
        }

        const nextStep = data.n;
        const value = data.v;

        const rendered = await this.engine.handleButtonClick(userId, nextStep, value);
        await this.max.answerCallback(callbackId, rendered.text, rendered.buttons);

        // Если автопереход (например, сброс порта свитча)
        if (rendered.isAutoTransition && rendered.next) {
          setTimeout(async () => {
            const nextRendered = await this.engine.transitionTo(this.engine.getSession(userId), rendered.next);
            await this.max.sendMessage({ userId }, nextRendered.text, nextRendered.buttons);
          }, 4000);
        }
        return;
      }

      // 3. Новое текстовое сообщение от пользователя (message_created)
      if (type === 'message_created' && update.message) {
        const msg = update.message;
        const sender = msg.sender || {};
        const userId = String(sender.user_id || 'unknown');
        const text = (msg.body ? msg.body.text : '').trim();

        if (!text) return;

        let rendered;
        if (text === '/start' || text.toLowerCase() === 'начать') {
          rendered = await this.engine.handleStart(userId);
        } else {
          rendered = await this.engine.handleTextInput(userId, text);
        }

        const recipient = { userId };
        await this.max.sendMessage(recipient, rendered.text, rendered.buttons);

        if (rendered.isAutoTransition && rendered.next) {
          setTimeout(async () => {
            const nextRendered = await this.engine.transitionTo(this.engine.getSession(userId), rendered.next);
            await this.max.sendMessage(recipient, nextRendered.text, nextRendered.buttons);
          }, 4000);
        }
      }
    } catch (err) {
      console.error('[MaxHandler Error]', err);
    }
  }

  // Запуск Long Polling для локальной отладки с платформой MAX
  async startPolling() {
    console.log('[MAX Bot] Запущен режим Long Polling с platform-api2.max.ru...');
    let marker = null;
    while (true) {
      try {
        const res = await this.max.getUpdates(marker);
        if (res && res.updates) {
          for (const u of res.updates) {
            await this.handleUpdate(u);
          }
          if (res.marker) {
            marker = res.marker;
          }
        }
      } catch (err) {
        console.error('[MAX Polling Error]', err.message);
        await new Promise(r => setTimeout(r, 5000));
      }
    }
  }
}
