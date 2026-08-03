import fs from 'node:fs';
import admin from 'firebase-admin';
import { config } from '../config/env.js';
import { logger } from '../infrastructure/logger.js';
import { pushCounter } from '../infrastructure/metrics.js';

class FcmService {
  private initialized = false;

  constructor() {
    this.init();
  }

  private init() {
    if (!config.firebaseServiceAccount) {
      logger.warn('[fcm] FIREBASE_SERVICE_ACCOUNT не задан');
      return;
    }
    if (!fs.existsSync(config.firebaseServiceAccount)) {
      logger.warn(`[fcm] Файл ключ-файла не найден: ${config.firebaseServiceAccount}`);
      return;
    }
    try {
      const sa = JSON.parse(fs.readFileSync(config.firebaseServiceAccount, 'utf8'));
      admin.initializeApp({ credential: admin.credential.cert(sa) });
      this.initialized = true;
      logger.info('[fcm] Firebase Admin SDK успешно инициализирован');
    } catch (err) {
      logger.error({ err }, '[fcm] Ошибка инициализации Firebase');
    }
  }

  isFcmEnabled(): boolean {
    return this.initialized;
  }

  async sendMulticast(params: {
    tokens: string[];
    title: string;
    body: string;
    data?: Record<string, string>;
    imageUrl?: string | null;
  }) {
    const { tokens, title, body, data, imageUrl } = params;
    if (!this.initialized || tokens.length === 0) {
      return { successCount: 0, failureCount: tokens.length };
    }

    const payload: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title,
        body,
        ...(imageUrl ? { imageUrl } : {}),
      },
      data: data ?? {},
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'default',
          ...(imageUrl ? { imageUrl } : {}),
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            contentAvailable: true,
            mutableContent: true,
          },
        },
        fcmOptions: imageUrl ? { imageUrl } : undefined,
      },
    };

    // Firebase multicast максимум 500 токенов за один запрос
    const BATCH_SIZE = 500;
    let totalSuccess = 0;
    let totalFailure = 0;

    for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
      const batchTokens = tokens.slice(i, i + BATCH_SIZE);
      try {
        const response = await admin.messaging().sendEachForMulticast({
          ...payload,
          tokens: batchTokens,
        });
        totalSuccess += response.successCount;
        totalFailure += response.failureCount;
      } catch (err) {
        logger.error({ err }, '[fcm] Ошибка отправки пакета пушей');
        totalFailure += batchTokens.length;
      }
    }

    pushCounter.inc({ status: 'success' }, totalSuccess);
    pushCounter.inc({ status: 'failure' }, totalFailure);

    return { successCount: totalSuccess, failureCount: totalFailure };
  }
}

export const fcmService = new FcmService();
