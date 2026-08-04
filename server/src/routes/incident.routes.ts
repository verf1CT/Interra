import { Router } from 'express';
import { incidentController } from '../controllers/incident.controller.js';
import { requireAdmin } from '../middlewares/auth.middleware.js';
import { validateBody } from '../middlewares/validate.middleware.js';
import { IncidentCreateSchema } from '../domain/schemas.js';

export const incidentRouter = Router();

// Public endpoints (for mobile app)
incidentRouter.get('/', incidentController.listActive);
incidentRouter.get('/history', incidentController.listHistory);

// Admin-only endpoints
incidentRouter.post('/', requireAdmin, validateBody(IncidentCreateSchema), incidentController.create);
incidentRouter.patch('/:id/resolve', requireAdmin, incidentController.resolve);
