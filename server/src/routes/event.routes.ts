import { Router } from 'express';
import { eventController } from '../controllers/event.controller.js';
import { validateBody } from '../middlewares/validate.middleware.js';
import { OpenedEventSchema } from '../domain/schemas.js';
import { deviceRateLimiter } from '../middlewares/rate-limiter.middleware.js';

export const eventsRouter = Router();

eventsRouter.post('/opened', deviceRateLimiter, validateBody(OpenedEventSchema), eventController.opened);
