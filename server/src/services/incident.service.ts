import { IncidentRepository, IncidentRow } from '../repositories/incident.repository.js';
import { broadcastService } from './broadcast.service.js';
import { sendTelegramAlert, defaultReplyKeyboard } from '../infrastructure/telegram.js';
import { logger } from '../infrastructure/logger.js';

export class IncidentService {
  constructor(private incidentRepo = new IncidentRepository()) {}

  async createIncident(params: {
    title: string;
    description?: string;
    type?: string;
    affectedArea?: string;
  }): Promise<IncidentRow> {
    const { title, description, type, affectedArea } = params;
    const { id } = this.incidentRepo.create({ title, description, type, affectedArea });
    const incident = this.incidentRepo.getById(Number(id))!;

    const isPlanned = incident.type === 'planned_work';
    const emoji = isPlanned ? '🔧' : '🚨';
    const label = isPlanned ? 'Плановые работы' : 'Авария';
    const pushTitle = `${emoji} ${label}`;
    const pushBody = affectedArea ? `${title} (${affectedArea})` : title;

    // Push all subscribers
    try {
      await broadcastService.runBroadcast({
        title: pushTitle,
        body: pushBody,
        target: { type: 'all' },
        screen: 'incidents',
      });
    } catch (err) {
      logger.error({ err }, '[incidents] Ошибка отправки пуш-уведомления об инциденте');
    }

    // Telegram alert
    const areaText = affectedArea ? `\nРайон: <b>${affectedArea}</b>` : '';
    const descText = description ? `\nОписание: <i>${description}</i>` : '';
    await sendTelegramAlert(
      `${emoji} <b>${label} #${id}</b>\n` +
      `----------------------------------\n` +
      `${title}${areaText}${descText}\n` +
      `----------------------------------\n` +
      `Закрыть: <code>/resolve ${id}</code>`,
      defaultReplyKeyboard
    );

    logger.info({ incidentId: id, type: incident.type }, '[incidents] Создан новый инцидент');
    return incident;
  }

  async resolveIncident(id: number): Promise<IncidentRow | null> {
    const incident = this.incidentRepo.getById(id);
    if (!incident || incident.status === 'resolved') return null;

    const { changes } = this.incidentRepo.resolve(id);
    if (changes === 0) return null;

    const resolved = this.incidentRepo.getById(id)!;

    // Push "resolved" notification
    try {
      await broadcastService.runBroadcast({
        title: '✅ Проблема устранена',
        body: incident.title,
        target: { type: 'all' },
        screen: 'incidents',
      });
    } catch (err) {
      logger.error({ err }, '[incidents] Ошибка отправки пуша о закрытии инцидента');
    }

    await sendTelegramAlert(
      `✅ <b>Инцидент #${id} закрыт</b>\n` +
      `----------------------------------\n` +
      `${incident.title}\n` +
      `----------------------------------`,
      defaultReplyKeyboard
    );

    logger.info({ incidentId: id }, '[incidents] Инцидент закрыт');
    return resolved;
  }

  listActive(): IncidentRow[] {
    return this.incidentRepo.listActive();
  }

  listRecent(limit = 20): IncidentRow[] {
    return this.incidentRepo.listRecent(limit);
  }
}

export const incidentService = new IncidentService();
