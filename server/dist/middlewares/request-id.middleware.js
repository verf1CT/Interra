import { randomUUID } from 'node:crypto';
import { requestStore } from '../infrastructure/async-context.js';
export function requestIdMiddleware(req, res, next) {
    const requestId = req.headers['x-request-id'] || randomUUID();
    res.setHeader('x-request-id', requestId);
    requestStore.run({ requestId }, () => next());
}
