import { DeviceRepository } from '../repositories/device.repository.js';
import { BroadcastRepository } from '../repositories/broadcast.repository.js';
import { fcmService } from './fcm.service.js';
import { logger } from '../infrastructure/logger.js';

export class BroadcastService {
  constructor(
    private deviceRepo = new DeviceRepository(),
    private broadcastRepo = new BroadcastRepository()
  ) {}

  async runBroadcast(params: {
    title: string;
    body: string;
    target: { type: 'all' | 'segment' | 'login'; value?: string };
    data?: Record<string, unknown>;
    imageUrl?: string | null;
    link?: string | null;
  }) {
    const { title, body, target, data, imageUrl, link } = params;
    const tokens = this.deviceRepo.selectTokensByTarget(target);

    // До рассылки создаём запись в БД, чтобы получить broadcast ID (`bid`)
    const logRes = this.broadcastRepo.logBroadcast({
      title,
      body,
      data,
      target,
      recipients: tokens.length,
      successCount: 0,
      failureCount: 0,
    });
    const broadcastId = logRes.lastInsertRowid;

    // В дата-пейлоад пробрасываем bid (для сбора статистики открытий) и link
    const fcmData: Record<string, string> = {};
    if (data) {
      for (const [k, v] of Object.entries(data)) {
        if (v != null) fcmData[k] = String(v);
      }
    }
    fcmData.bid = String(broadcastId);
    if (link) fcmData.link = link;

    logger.info(
      { broadcastId, recipients: tokens.length, target },
      '[broadcast] Отправка рассылки...'
    );

    const { successCount, failureCount } = await fcmService.sendMulticast({
      tokens,
      title,
      body,
      data: fcmData,
      imageUrl,
    });

    this.broadcastRepo.updateBroadcastResult(broadcastId, successCount, failureCount);

    logger.info(
      { broadcastId, successCount, failureCount },
      '[broadcast] Рассылка завершена'
    );

    return { broadcastId, recipients: tokens.length, successCount, failureCount };
  }
}

export const broadcastService = new BroadcastService();
