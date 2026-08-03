import { describe, it, expect, beforeAll } from 'vitest';
import request from 'supertest';
import { app } from '../src/index.js';
import { config } from '../src/config/env.js';

describe('Server API Integration Tests', () => {
  it('GET /healthz returns 200 ok', async () => {
    const res = await request(app).get('/healthz');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('status', 'ok');
    expect(res.body).toHaveProperty('uptime');
  });

  it('GET /readyz returns 200 ready', async () => {
    const res = await request(app).get('/readyz');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ready', db: 'connected' });
  });

  it('GET /metrics returns prometheus metrics format', async () => {
    const res = await request(app).get('/metrics');
    expect(res.status).toBe(200);
    expect(res.text).toContain('http_request_duration_seconds');
  });

  describe('Device API', () => {
    it('POST /api/devices/register validates missing token', async () => {
      const res = await request(app).post('/api/devices/register').send({});
      expect(res.status).toBe(400);
      expect(res.body).toHaveProperty('error');
    });

    it('POST /api/devices/register registers a valid device', async () => {
      const res = await request(app).post('/api/devices/register').send({
        token: 'test-token-123',
        clientLogin: 'user123',
        platform: 'ios',
        appVersion: '1.0.0',
        segments: ['beta'],
      });
      expect(res.status).toBe(200);
      expect(res.body).toEqual({ ok: true, deviceId: expect.any(Number) });
    });

    it('POST /api/devices/unregister unregisters device', async () => {
      const res = await request(app).post('/api/devices/unregister').send({
        token: 'test-token-123',
      });
      expect(res.status).toBe(200);
      expect(res.body).toEqual({ ok: true });
    });
  });

  describe('Events API', () => {
    it('POST /api/events/opened tracks open event', async () => {
      const res = await request(app).post('/api/events/opened').send({ bid: 1 });
      expect(res.status).toBe(200);
      expect(res.body).toEqual({ ok: true });
    });

    it('POST /api/events/opened rejects invalid bid', async () => {
      const res = await request(app).post('/api/events/opened').send({ bid: -5 });
      expect(res.status).toBe(400);
      expect(res.body).toHaveProperty('error');
    });
  });

  describe('Admin API Auth', () => {
    it('GET /api/admin/stats rejects request without token', async () => {
      const res = await request(app).get('/api/admin/stats');
      expect(res.status).toBe(401);
    });

    it('GET /api/admin/stats allows request with valid token', async () => {
      const res = await request(app)
        .get('/api/admin/stats')
        .set('Authorization', `Bearer ${config.adminToken || 'test-secret'}`);

      if (!config.adminToken) {
        expect(res.status).toBe(401);
      } else {
        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('devices');
        expect(res.body).toHaveProperty('totals');
      }
    });
  });
});
