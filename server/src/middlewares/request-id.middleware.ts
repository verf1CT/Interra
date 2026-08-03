import { Request, Response, NextFunction } from 'express';
import { randomUUID } from 'node:crypto';
import { requestStore } from '../infrastructure/async-context.js';

export function requestIdMiddleware(req: Request, res: Response, next: NextFunction) {
  const requestId = (req.headers['x-request-id'] as string) || randomUUID();
  res.setHeader('x-request-id', requestId);
  requestStore.run({ requestId }, () => next());
}
