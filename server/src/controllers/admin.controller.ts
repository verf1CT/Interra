import { Request, Response } from 'express';
import { DeviceRepository } from '../repositories/device.repository.js';
import { BroadcastRepository } from '../repositories/broadcast.repository.js';
import { broadcastService } from '../services/broadcast.service.js';
import { fcmService } from '../services/fcm.service.js';
import { BroadcastDto } from '../domain/schemas.js';
import { ValidationError } from '../domain/errors.js';

export class AdminController {
  constructor(
    private deviceRepo = new DeviceRepository(),
    private broadcastRepo = new BroadcastRepository()
  ) {}

  getStats = (_req: Request, res: Response) => {
    res.json({
      fcmEnabled: fcmService.isFcmEnabled(),
      devices: this.deviceRepo.getStats(),
      totals: this.broadcastRepo.getBroadcastStats(),
      broadcasts: this.broadcastRepo.getRecentBroadcasts(),
    });
  };

  createBroadcast = async (req: Request, res: Response) => {
    const body: BroadcastDto = req.body;
    const { title, body: msgBody, target, data, imageUrl, link, sendAt } = body;

    // отложенная рассылка
    if (sendAt) {
      const when = new Date(sendAt);
      if (Number.isNaN(when.getTime())) {
        throw new ValidationError('sendAt — некорректная дата/время');
      }
      if (when.getTime() <= Date.now()) {
        throw new ValidationError('sendAt должен быть в будущем');
      }
      const r = this.broadcastRepo.createScheduled({
        title,
        body: msgBody,
        data,
        imageUrl,
        link,
        target,
        sendAt: when.toISOString(),
      });
      return res.json({ ok: true, scheduled: true, id: r.lastInsertRowid, sendAt: when.toISOString() });
    }

    // немедленная отправка
    const result = await broadcastService.runBroadcast({
      title,
      body: msgBody,
      target,
      data,
      imageUrl,
      link,
    });
    res.json({ ok: true, ...result });
  };

  listScheduled = (_req: Request, res: Response) => {
    res.json({ scheduled: this.broadcastRepo.listScheduled() });
  };

  cancelScheduled = (req: Request, res: Response) => {
    const id = Number(req.params.id);
    if (!id || Number.isNaN(id)) {
      throw new ValidationError('id некорректен');
    }
    const r = this.broadcastRepo.cancelScheduled(id);
    res.json({ ok: true, canceled: r.changes });
  };
}

export const adminController = new AdminController();
