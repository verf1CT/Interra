import { Router } from 'express';
import { deviceController } from '../controllers/device.controller.js';
import { validateBody } from '../middlewares/validate.middleware.js';
import { deviceRateLimiter } from '../middlewares/rate-limiter.middleware.js';
import { RegisterDeviceSchema, UnregisterDeviceSchema } from '../domain/schemas.js';
export const devicesRouter = Router();
devicesRouter.post('/register', deviceRateLimiter, validateBody(RegisterDeviceSchema), deviceController.register);
devicesRouter.post('/unregister', validateBody(UnregisterDeviceSchema), deviceController.unregister);
