import pino from 'pino';
import { config } from '../config/env.js';
import { requestStore } from './async-context.js';
export const logger = pino({
    level: config.nodeEnv === 'test' ? 'silent' : 'info',
    mixin() {
        const store = requestStore.getStore();
        return store?.requestId ? { requestId: store.requestId } : {};
    },
    transport: config.nodeEnv === 'development'
        ? {
            target: 'pino-pretty',
            options: { colorize: true, ignore: 'pid,hostname' },
        }
        : undefined,
});
