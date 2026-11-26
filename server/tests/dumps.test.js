import { describe, it, expect } from 'vitest';
import { saveDump, listDumps, getDump } from '../src/db.js';

describe('дампы кабинета', () => {
  it('сохраняются и читаются, в списке без тела', () => {
    const id = saveDump({ platform: 'ios', appVersion: '1.0.0', body: 'страница кабинета' });
    const items = listDumps();
    expect(items[0].id).toBe(Number(id));
    expect(items[0].body).toBeUndefined();
    expect(items[0].size).toBe(Buffer.byteLength('страница кабинета', 'utf8'));
    expect(getDump(id).body).toBe('страница кабинета');
  });

  it('хранится не больше 20 последних', () => {
    for (let i = 0; i < 25; i++) saveDump({ body: `дамп ${i}` });
    const items = listDumps();
    expect(items.length).toBe(20);
    expect(getDump(items[0].id).body).toBe('дамп 24');
  });
});
