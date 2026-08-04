import { Request, Response } from 'express';
import { incidentService } from '../services/incident.service.js';
import { IncidentCreateDto } from '../domain/schemas.js';

export class IncidentController {
  listActive = (_req: Request, res: Response) => {
    res.json({ incidents: incidentService.listActive() });
  };

  listHistory = (_req: Request, res: Response) => {
    res.json({ incidents: incidentService.listRecent() });
  };

  create = async (req: Request, res: Response) => {
    const body: IncidentCreateDto = req.body;
    const incident = await incidentService.createIncident(body);
    res.status(201).json({ ok: true, incident });
  };

  resolve = async (req: Request, res: Response) => {
    const id = Number(req.params.id);
    if (!id || Number.isNaN(id)) {
      return res.status(400).json({ error: 'Некорректный ID инцидента' });
    }
    const incident = await incidentService.resolveIncident(id);
    if (!incident) {
      return res.status(404).json({ error: 'Инцидент не найден или уже закрыт' });
    }
    res.json({ ok: true, incident });
  };
}

export const incidentController = new IncidentController();
