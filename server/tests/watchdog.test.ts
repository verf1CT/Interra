import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { watchdogService } from '../src/services/watchdog.service.js';

describe('Watchdog Health Monitoring Service', () => {
  beforeEach(() => {
    watchdogService.start();
  });

  afterEach(() => {
    watchdogService.stop();
  });

  it('выполняет проверку здоровья компонентов (checkHealth)', async () => {
    const health = await watchdogService.checkHealth();
    expect(health).toHaveProperty('db', true);
    expect(health).toHaveProperty('memory', true);
  });
});
