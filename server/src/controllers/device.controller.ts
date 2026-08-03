import { Request, Response } from 'express';
import { DeviceRepository } from '../repositories/device.repository.js';
import { RegisterDeviceDto, UnregisterDeviceDto } from '../domain/schemas.js';

export class DeviceController {
  constructor(private deviceRepo = new DeviceRepository()) {}

  register = (req: Request, res: Response) => {
    const body: RegisterDeviceDto = req.body;
    const device = this.deviceRepo.upsert(body);
    res.json({ ok: true, deviceId: device.id });
  };

  unregister = (req: Request, res: Response) => {
    const body: UnregisterDeviceDto = req.body;
    this.deviceRepo.deleteByToken(body.token);
    res.json({ ok: true });
  };
}

export const deviceController = new DeviceController();
