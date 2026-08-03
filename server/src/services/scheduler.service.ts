import { BroadcastRepository } from '../repositories/broadcast.repository.js';
import { broadcastService } from './broadcast.service.js';
import { logger } from '../infrastructure/logger.js';

const TICK_INTERVAL_MS = 15_000; // каждые 15 сек проверяем базу

export class SchedulerService {
  private timer?: NodeJS.Timeout;
  private running = false;
  private broadcastRepo = new BroadcastRepository();

  start() {
    if (this.running) return;
    this.running = true;
    logger.info('[scheduler] Фоновый планировщик отложенных рассылок запущен');
    this.timer = setInterval(() => this.tick(), TICK_INTERVAL_MS);
    this.tick();
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
    this.running = false;
    logger.info('[scheduler] Планировщик остановлен');
  }

  private async tick() {
    try {
      const nowIso = new Date().toISOString();
      const due = this.broadcastRepo.dueScheduled(nowIso);

      for (const item of due) {
        logger.info({ scheduledId: item.id, title: item.title }, '[scheduler] Обработка запланированной рассылки');
        this.broadcastRepo.markScheduledSent(item.id);

        let dataObj: Record<string, unknown> = {};
        try {
          dataObj = JSON.parse(item.data || '{}');
        } catch {
          // fallback
        }

        await broadcastService.runBroadcast({
          title: item.title,
          body: item.body,
          target: {
            type: item.target_type as 'all' | 'segment' | 'login',
            value: item.target_value ?? undefined,
          },
          data: dataObj,
          imageUrl: item.image_url,
          link: item.link,
        });
      }
    } catch (err) {
      logger.error({ err }, '[scheduler] Ошибка выполнения цикла планировщика');
    }
  }
}

export const schedulerService = new SchedulerService();
