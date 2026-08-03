import { DeviceRepository } from '../repositories/device.repository.js';
export class DeviceController {
    deviceRepo;
    constructor(deviceRepo = new DeviceRepository()) {
        this.deviceRepo = deviceRepo;
    }
    register = (req, res) => {
        const body = req.body;
        const device = this.deviceRepo.upsert(body);
        res.json({ ok: true, deviceId: device.id });
    };
    unregister = (req, res) => {
        const body = req.body;
        this.deviceRepo.deleteByToken(body.token);
        res.json({ ok: true });
    };
}
export const deviceController = new DeviceController();
