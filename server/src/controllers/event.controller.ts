import { Request, Response } from 'express';
import { BroadcastRepository } from '../repositories/broadcast.repository.js';
import { OpenedEventDto } from '../domain/schemas.js';

export class EventController {
  constructor(private broadcastRepo = new BroadcastRepository()) {}

  opened = (req: Request, res: Response) => {
    const body: OpenedEventDto = req.body;
    this.broadcastRepo.incrementOpens(body.bid);
    res.json({ ok: true });
  };
}

export const eventController = new EventController();
