import client from 'prom-client';
export const register = new client.Registry();
client.collectDefaultMetrics({ register });
export const httpRequestDurationMicroseconds = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duration of HTTP requests in seconds',
    labelNames: ['method', 'route', 'code'],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});
register.registerMetric(httpRequestDurationMicroseconds);
export const pushCounter = new client.Counter({
    name: 'fcm_push_total',
    help: 'Total FCM pushes sent',
    labelNames: ['status'],
});
register.registerMetric(pushCounter);
