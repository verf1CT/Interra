import { Router } from 'express';
import { eventController } from '../controllers/event.controller.js';
import { validateBody } from '../middlewares/validate.middleware.js';
import { OpenedEventSchema } from '../domain/schemas.js';
export const eventsRouter = Router();
eventsRouter.post('/opened', validateBody(OpenedEventSchema), eventController.opened);
