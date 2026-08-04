import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { app } from '../src/index.js';
import { config } from '../src/config/env.js';
import { db } from '../src/db/connection.js';

describe('E2E: Полный цикл рассылки (без моков)', () => {
  const testToken = `e2e-device-${Date.now()}`;
  const testLogin = `e2e-user-${Date.now()}`;

  it('1. Регистрирует устройство', async () => {
    const res = await request(app).post('/api/devices/register').send({
      token: testToken,
      clientLogin: testLogin,
      platform: 'android',
      appVersion: '1.0.0-e2e',
      segments: ['e2e'],
    });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true, deviceId: expect.any(Number) });
  });

  it('2. Отправляет broadcast и проверяет запись в БД', async () => {
    if (!config.adminToken) return; // без токена broadcast API недоступен

    const res = await request(app)
      .post('/api/admin/broadcast')
      .set('Authorization', `Bearer ${config.adminToken}`)
      .send({
        title: 'E2E Test Push',
        body: 'Это тестовая рассылка из интеграционного теста',
        target: { type: 'login', value: testLogin },
        screen: 'diagnostics',
      });

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('ok', true);
    expect(res.body).toHaveProperty('broadcastId');
    expect(res.body).toHaveProperty('recipients');

    // Проверяем, что запись создана в таблице broadcasts
    const bid = res.body.broadcastId;
    const row = db.prepare('SELECT * FROM broadcasts WHERE id = ?').get(bid) as Record<string, unknown> | undefined;
    expect(row).toBeDefined();
    expect(row?.title).toBe('E2E Test Push');
  }, 15000);

  it('3. Отправляет событие открытия (opened)', async () => {
    // Создаём broadcast-запись вручную для стабильного теста
    const insertRes = db.prepare(
      `INSERT INTO broadcasts (title, body, data, target_type, recipients, success_count, failure_count)
       VALUES ('E2E Open Test', 'body', '{}', 'all', 1, 1, 0)`
    ).run();
    const bid = insertRes.lastInsertRowid;

    const res = await request(app)
      .post('/api/events/opened')
      .send({ bid: Number(bid) });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true });

    // Проверяем, что opens увеличился
    const row = db.prepare('SELECT opens FROM broadcasts WHERE id = ?').get(bid) as { opens: number };
    expect(row.opens).toBeGreaterThanOrEqual(1);
  });

  it('4. Удаляет тестовое устройство', async () => {
    const res = await request(app).post('/api/devices/unregister').send({
      token: testToken,
    });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true });
  });
});
