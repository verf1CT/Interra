// Легковесный нативный клиент для Telegram Bot API (без внешних зависимостей)

export class TelegramClient {
  constructor(token) {
    this.token = token || process.env.TELEGRAM_BOT_TOKEN || '';
    this.baseUrl = `https://api.telegram.org/bot${this.token}`;
  }

  get isConfigured() {
    return Boolean(this.token && !this.token.includes('change-me'));
  }

  async call(method, payload = {}) {
    if (!this.isConfigured) {
      console.log(`[Telegram Dry-Run] Method: ${method}`, JSON.stringify(payload, null, 2));
      return { ok: true, result: { message_id: 1, mock: true } };
    }

    const res = await fetch(`${this.baseUrl}/${method}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    const data = await res.json();
    if (!data.ok) {
      console.error(`[Telegram Error] ${method}:`, data);
      throw new Error(`Telegram API Error: ${data.description}`);
    }
    return data;
  }

  async sendMessage(chatId, text, replyMarkup = null) {
    const payload = {
      chat_id: chatId,
      text,
      parse_mode: 'HTML'
    };
    if (replyMarkup) {
      payload.reply_markup = replyMarkup;
    }
    return await this.call('sendMessage', payload);
  }

  async editMessageText(chatId, messageId, text, replyMarkup = null) {
    const payload = {
      chat_id: chatId,
      message_id: messageId,
      text,
      parse_mode: 'HTML'
    };
    if (replyMarkup) {
      payload.reply_markup = replyMarkup;
    }
    return await this.call('editMessageText', payload);
  }

  async answerCallbackQuery(callbackQueryId, text = '') {
    return await this.call('answerCallbackQuery', {
      callback_query_id: callbackQueryId,
      text
    });
  }

  async setWebhook(url) {
    return await this.call('setWebhook', { url });
  }

  async getUpdates(offset = 0, timeout = 30) {
    if (!this.isConfigured) return { ok: true, result: [] };
    const res = await fetch(`${this.baseUrl}/getUpdates?offset=${offset}&timeout=${timeout}`);
    return await res.json();
  }
}
