// Официальный API-клиент платформы MAX (platform-api2.max.ru)
// Документация: https://dev.max.ru/docs-api/

import https from 'node:https';

export class MaxClient {
  constructor(token, options = {}) {
    this.token = token || process.env.MAX_BOT_TOKEN || '';
    this.baseUrl = options.baseUrl || 'https://platform-api2.max.ru';
  }

  get isConfigured() {
    return Boolean(
      this.token &&
      !this.token.includes('change-me') &&
      !this.token.includes('test-')
    );
  }

  async call(path, options = {}) {
    if (!this.isConfigured) {
      console.log(`[MAX Dry-Run] ${options.method || 'GET'} ${path}`, JSON.stringify(options.body, null, 2));
      return { ok: true, result: { message_id: 1, mock: true } };
    }

    const fullUrl = new URL(path, this.baseUrl);
    const headers = {
      Authorization: this.token,
      'Content-Type': 'application/json',
      ...options.headers
    };

    const payload = options.body ? JSON.stringify(options.body) : null;
    if (payload) {
      headers['Content-Length'] = Buffer.byteLength(payload);
    }

    return new Promise((resolve, reject) => {
      const req = https.request(
        fullUrl,
        {
          method: options.method || 'GET',
          headers,
          // platform-api2.max.ru использует сертификат Минцифры РФ
          rejectUnauthorized: false
        },
        (res) => {
          let rawData = '';
          res.on('data', chunk => { rawData += chunk; });
          res.on('end', () => {
            try {
              const parsed = rawData ? JSON.parse(rawData) : {};
              if (res.statusCode >= 200 && res.statusCode < 300) {
                resolve(parsed);
              } else {
                console.error(`[MAX API Error] ${path} status ${res.statusCode}:`, parsed);
                reject(new Error(`MAX API Error ${res.statusCode}: ${parsed.message || rawData}`));
              }
            } catch (err) {
              reject(new Error(`MAX API JSON parse error: ${err.message}`));
            }
          });
        }
      );

      req.on('error', err => reject(err));
      if (payload) {
        req.write(payload);
      }
      req.end();
    });
  }

  // Конвертация кнопок движка бота в формат inline_keyboard MAX
  formatKeyboard(buttons) {
    if (!buttons || buttons.length === 0) return null;

    const rows = [];
    for (const btn of buttons) {
      if (btn.url) {
        rows.push([
          {
            type: 'link',
            text: btn.text,
            url: btn.url
          }
        ]);
      } else {
        const payload = JSON.stringify({
          n: btn.next,
          v: btn.value || undefined
        });
        rows.push([
          {
            type: 'callback',
            text: btn.text,
            payload
          }
        ]);
      }
    }

    return {
      type: 'inline_keyboard',
      payload: {
        buttons: rows
      }
    };
  }

  // Отправка сообщения пользователю или в чат
  async sendMessage(recipient, text, buttons = null) {
    const query = recipient.userId
      ? `user_id=${encodeURIComponent(recipient.userId)}`
      : `chat_id=${encodeURIComponent(recipient.chatId)}`;

    const attachments = [];
    const keyboard = this.formatKeyboard(buttons);
    if (keyboard) {
      attachments.push(keyboard);
    }

    const payload = {
      text,
      attachments: attachments.length > 0 ? attachments : undefined
    };

    return await this.call(`/messages?${query}`, {
      method: 'POST',
      body: payload
    });
  }

  // Ответ на нажатие кнопки (callback)
  async answerCallback(callbackId, text, buttons = null) {
    const attachments = [];
    const keyboard = this.formatKeyboard(buttons);
    if (keyboard) {
      attachments.push(keyboard);
    }

    const payload = {
      message: {
        text,
        attachments: attachments.length > 0 ? attachments : undefined
      }
    };

    return await this.call(`/answers?callback_id=${encodeURIComponent(callbackId)}`, {
      method: 'POST',
      body: payload
    });
  }

  // Подписка на Webhook обновлений
  async setWebhook(webhookUrl) {
    return await this.call('/subscriptions', {
      method: 'POST',
      body: { url: webhookUrl }
    });
  }

  // Получение обновлений через Long Polling
  async getUpdates(marker = null, limit = 50) {
    if (!this.isConfigured) return { updates: [] };
    const query = marker ? `?marker=${encodeURIComponent(marker)}&limit=${limit}` : `?limit=${limit}`;
    return await this.call(`/updates${query}`);
  }
}
