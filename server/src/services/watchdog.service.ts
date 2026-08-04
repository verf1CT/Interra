import v8 from 'node:v8';
import { db } from '../db/connection.js';
import { logger } from '../infrastructure/logger.js';
import { sendTelegramAlert } from '../infrastructure/telegram.js';

const CHECK_INTERVAL_MS = 30_000; // каждые 30 секунд
const HEAP_LIMIT_MB = 450; // порог памяти для предупреждения (MB)

interface WatchdogState {
  dbHealthy: boolean;
  memoryHealthy: boolean;
  lastDbAlertTime: number;
  lastMemAlertTime: number;
}

export class WatchdogService {
  private timer?: NodeJS.Timeout;
  private running = false;

  private state: WatchdogState = {
    dbHealthy: true,
    memoryHealthy: true,
    lastDbAlertTime: 0,
    lastMemAlertTime: 0,
  };

  start(): void {
    if (this.running) return;
    this.running = true;
    logger.info('[watchdog] Сервис авто-мониторинга сбоев запущен (интервал: 30с)');

    // Отслеживаем необработанные ошибки процесса Node.js
    this.setupProcessHandlers();

    // Запускаем периодическую проверку
    this.timer = setInterval(() => this.checkHealth(), CHECK_INTERVAL_MS);
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
    this.running = false;
    logger.info('[watchdog] Мониторинг сбоев остановлен');
  }

  private setupProcessHandlers(): void {
    process.on('uncaughtException', (err: Error) => {
      logger.fatal({ err }, '[watchdog] Uncaught Exception!');
      const alertMsg =
        `🚨 <b>CRITICAL: Необработанная исключительная ошибка процесса!</b>\n` +
        `----------------------------------\n` +
        `Ошибка: <code>${err.name}</code>: ${err.message}\n` +
        `Стек-трейс:\n<code>${(err.stack || '').slice(0, 500)}</code>\n` +
        `----------------------------------`;
      sendTelegramAlert(alertMsg);
    });

    process.on('unhandledRejection', (reason: unknown) => {
      logger.error({ reason }, '[watchdog] Unhandled Rejection!');
      const reasonStr = reason instanceof Error ? reason.message : String(reason);
      const alertMsg =
        `🚨 <b>CRITICAL: Необработанный Promise Rejection!</b>\n` +
        `----------------------------------\n` +
        `Причина: <code>${reasonStr}</code>\n` +
        `----------------------------------`;
      sendTelegramAlert(alertMsg);
    });
  }

  async checkHealth(): Promise<{ db: boolean; memory: boolean }> {
    const dbOk = this.checkDbHealth();
    const memOk = this.checkMemoryHealth();
    return { db: dbOk, memory: memOk };
  }

  private checkDbHealth(): boolean {
    let dbOk = false;
    let errorMessage = '';

    try {
      const row = db.prepare('SELECT 1 AS ok').get() as { ok: number } | undefined;
      dbOk = row?.ok === 1;
    } catch (err) {
      dbOk = false;
      errorMessage = (err as Error).message;
    }

    const now = Date.now();

    if (!dbOk) {
      logger.error({ error: errorMessage }, '[watchdog] БД SQLite не отвечает');
      // Алерт отправляем только раз в 5 минут при непрерывном сбое
      if (this.state.dbHealthy || now - this.state.lastDbAlertTime > 300_000) {
        this.state.dbHealthy = false;
        this.state.lastDbAlertTime = now;

        const alertMsg =
          `🚨 <b>CRITICAL ALERT: Потеряно соединение с SQLite БД!</b>\n` +
          `----------------------------------\n` +
          `Статус: ❌ Offline / Corrupted\n` +
          `Ошибка: <code>${errorMessage || 'SELECT 1 не вернул результат'}</code>\n` +
          `Время: <code>${new Date().toLocaleString('ru-RU')}</code>\n` +
          `----------------------------------`;
        sendTelegramAlert(alertMsg);
      }
    } else {
      // Если до этого был сбой — отправляем уведомление о восстановлении
      if (!this.state.dbHealthy) {
        this.state.dbHealthy = true;
        const recoveredMsg =
          `✅ <b>RECOVERED: Соединение с SQLite БД восстановлено!</b>\n` +
          `----------------------------------\n` +
          `Статус: 🟢 Online & Healthy\n` +
          `Время: <code>${new Date().toLocaleString('ru-RU')}</code>\n` +
          `----------------------------------`;
        sendTelegramAlert(recoveredMsg);
      }
    }

    return dbOk;
  }

  private checkMemoryHealth(): boolean {
    const memoryUsage = process.memoryUsage();
    const heapUsedMb = Math.round(memoryUsage.heapUsed / 1024 / 1024);
    const memOk = heapUsedMb < HEAP_LIMIT_MB;
    const now = Date.now();

    if (!memOk) {
      logger.warn({ heapUsedMb, limitMb: HEAP_LIMIT_MB }, '[watchdog] Высокое потребление RAM');
      if (this.state.memoryHealthy || now - this.state.lastMemAlertTime > 300_000) {
        this.state.memoryHealthy = false;
        this.state.lastMemAlertTime = now;

        const alertMsg =
          `⚠️ <b>WARNING ALERT: Высокое потребление оперативной памяти (RAM)!</b>\n` +
          `----------------------------------\n` +
          `Использовано Heap: <b>${heapUsedMb} MB</b> (Лимит: ${HEAP_LIMIT_MB} MB)\n` +
          `RSS: <b>${Math.round(memoryUsage.rss / 1024 / 1024)} MB</b>\n` +
          `----------------------------------`;
        sendTelegramAlert(alertMsg);
      }
    } else {
      if (!this.state.memoryHealthy) {
        this.state.memoryHealthy = true;
        const recoveredMsg =
          `✅ <b>RECOVERED: Потребление памяти вернулось в норму</b>\n` +
          `----------------------------------\n` +
          `Текущий Heap: <b>${heapUsedMb} MB</b>\n` +
          `----------------------------------`;
        sendTelegramAlert(recoveredMsg);
      }
    }

    return memOk;
  }
}

export const watchdogService = new WatchdogService();
