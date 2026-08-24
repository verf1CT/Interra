import { describe, it, expect, beforeEach } from 'vitest';
import { db, upsertDevice, deleteDevice, selectTokens, logBroadcast, updateBroadcastResult, incrementOpens, stats, recentBroadcasts, createScheduled, listScheduled, cancelScheduled, dueScheduled, markScheduledSent, broadcastStats } from '../src/db.js';

describe('db.js', () => {
  beforeEach(() => {
    db.exec('DELETE FROM devices');
    db.exec('DELETE FROM broadcasts');
    db.exec('DELETE FROM scheduled_broadcasts');
  });

  it('upserts and retrieves devices', () => {
    upsertDevice({ token: 't1', clientLogin: 'log1', platform: 'android', appVersion: '1', segments: ['a'], prefs: {b:1} });
    let dev = db.prepare('SELECT * FROM devices WHERE token = ?').get('t1');
    expect(dev.client_login).toBe('log1');

    upsertDevice({ token: 't1', clientLogin: 'log2' });
    dev = db.prepare('SELECT * FROM devices WHERE token = ?').get('t1');
    expect(dev.client_login).toBe('log2');
    expect(dev.platform).toBe('android'); // untouched
  });

  it('deletes devices', () => {
    upsertDevice({ token: 't1' });
    deleteDevice('t1');
    expect(db.prepare('SELECT * FROM devices WHERE token = ?').get('t1')).toBeUndefined();
  });

  it('selects tokens by target', () => {
    upsertDevice({ token: 't1', clientLogin: 'u1', segments: ['s1'] });
    upsertDevice({ token: 't2', clientLogin: 'u2', segments: ['s1', 's2'] });

    expect(selectTokens({ type: 'all' }).length).toBe(2);
    expect(selectTokens({ type: 'login', value: 'u1' })).toEqual(['t1']);
    expect(selectTokens({ type: 'segment', value: 's2' })).toEqual(['t2']);
    expect(selectTokens({ type: 'invalid' })).toEqual([]);
  });

  it('handles broadcast logs and stats', () => {
    const info = logBroadcast({ title: 't', body: 'b', target: { type: 'all' }, recipients: 10, successCount: 8, failureCount: 2 });
    const id = info.lastInsertRowid;
    updateBroadcastResult(id, 9, 1);
    incrementOpens(id);

    const logs = recentBroadcasts(10);
    expect(logs.length).toBe(1);
    expect(logs[0].success_count).toBe(9);
    expect(logs[0].opens).toBe(1);

    const bs = broadcastStats();
    expect(bs.total).toBe(1);
    expect(bs.success).toBe(9);
    expect(bs.opens).toBe(1);
  });

  it('computes device stats', () => {
    upsertDevice({ token: 't1', platform: 'ios', clientLogin: 'a' });
    upsertDevice({ token: 't2', platform: 'android' });
    const s = stats();
    expect(s.total).toBe(2);
    expect(s.withLogin).toBe(1);
    expect(s.byPlatform.find(p => p.platform === 'ios').n).toBe(1);
  });

  it('handles scheduled broadcasts', () => {
    const now = new Date().toISOString();
    const future = new Date(Date.now() + 10000).toISOString();
    const past = new Date(Date.now() - 10000).toISOString();

    createScheduled({ title: 'future', body: 'b', target: { type: 'all' }, sendAt: future });
    createScheduled({ title: 'past', body: 'b', target: { type: 'all' }, sendAt: past });
    
    expect(listScheduled().length).toBe(2);
    expect(dueScheduled(now).length).toBe(1);
    expect(dueScheduled(now)[0].title).toBe('past');

    const idToCancel = dueScheduled(now)[0].id;
    cancelScheduled(idToCancel);
    expect(dueScheduled(now).length).toBe(0);

    const fId = listScheduled().find(s => s.title === 'future').id;
    markScheduledSent(fId);
    expect(listScheduled().length).toBe(0); // none pending
  });
});
