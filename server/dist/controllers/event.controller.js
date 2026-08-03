import { BroadcastRepository } from '../repositories/broadcast.repository.js';
export class EventController {
    broadcastRepo;
    constructor(broadcastRepo = new BroadcastRepository()) {
        this.broadcastRepo = broadcastRepo;
    }
    opened = (req, res) => {
        const body = req.body;
        this.broadcastRepo.incrementOpens(body.bid);
        res.json({ ok: true });
    };
}
export const eventController = new EventController();
