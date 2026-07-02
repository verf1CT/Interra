import fs from 'node:fs';
import path from 'node:path';
import Database from 'better-sqlite3';
import { config } from './config.js';

fs.mkdirSync(path.dirname(config.dbPath), { recursive: true });

export const db = new Database(config.dbPath);
db.pragma('journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS devices (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    token        TEXT NOT NULL UNIQUE,
    client_login TEXT,
    platform     TEXT,
    app_version  TEXT,
    segments     TEXT NOT NULL DEFAULT '[]',
    prefs        TEXT NOT NULL DEFAULT '{}',
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_devices_login ON devices(client_login);

  CREATE TABLE IF NOT EXISTS broadcasts (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    title         TEXT NOT NULL,
    body          TEXT NOT NULL,
    data          TEXT NOT NULL DEFAULT '{}',
    target_type   TEXT NOT NULL,
    target_value  TEXT,
    recipients    INTEGER NOT NULL DEFAULT 0,
    success_count INTEGER NOT NULL DEFAULT 0,
    failure_count INTEGER NOT NULL DEFAULT 0,
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
  );
`);

/**
 * создаёт или обновляет устройство по его push-токену.
 * Возвращает строку устройства
 */
export function upsertDevice({ token, clientLogin, platform, appVersion, segments, prefs }) {
  const existing = db.prepare('SELECT * FROM devices WHERE token = ?').get(token);

  if (existing) {
    db.prepare(
      `UPDATE devices SET
         client_login = COALESCE(@clientLogin, client_login),
         platform     = COALESCE(@platform, platform),
         app_version  = COALESCE(@appVersion, app_version),
         segments     = COALESCE(@segments, segments),
         prefs        = COALESCE(@prefs, prefs),
         updated_at   = datetime('now')
       WHERE token = @token`
    ).run({
      token,
      clientLogin: clientLogin ?? null,
      platform: platform ?? null,
      appVersion: appVersion ?? null,
      segments: segments ? JSON.stringify(segments) : null,
      prefs: prefs ? JSON.stringify(prefs) : null,
    });
  } else {
    db.prepare(
      `INSERT INTO devices (token, client_login, platform, app_version, segments, prefs)
       VALUES (@token, @clientLogin, @platform, @appVersion, @segments, @prefs)`
    ).run({
      token,
      clientLogin: clientLogin ?? null,
      platform: platform ?? null,
      appVersion: appVersion ?? null,
      segments: JSON.stringify(segments ?? []),
      prefs: JSON.stringify(prefs ?? {}),
    });
  }

  return db.prepare('SELECT * FROM devices WHERE token = ?').get(token);
}

export function deleteDevice(token) {
  return db.prepare('DELETE FROM devices WHERE token = ?').run(token);
}

/**
 * возвращает push-токены устройств по цели рассылки.
 * @param {{type: 'all'|'segment'|'login', value?: string}} target
 */
export function selectTokens(target) {
  if (target.type === 'all') {
    return db.prepare('SELECT token FROM devices').all().map((r) => r.token);
  }
  if (target.type === 'login') {
    return db
      .prepare('SELECT token FROM devices WHERE client_login = ?')
      .all(target.value)
      .map((r) => r.token);
  }
  if (target.type === 'segment') {
    // segments хранится JSON-массивом; ищем вхождение значения
    return db
      .prepare(`SELECT token, segments FROM devices`)
      .all()
      .filter((r) => {
        try {
          return JSON.parse(r.segments).includes(target.value);
        } catch {
          return false;
        }
      })
      .map((r) => r.token);
  }
  return [];
}

export function logBroadcast({ title, body, data, target, recipients, successCount, failureCount }) {
  return db
    .prepare(
      `INSERT INTO broadcasts (title, body, data, target_type, target_value, recipients, success_count, failure_count)
       VALUES (@title, @body, @data, @targetType, @targetValue, @recipients, @successCount, @failureCount)`
    )
    .run({
      title,
      body,
      data: JSON.stringify(data ?? {}),
      targetType: target.type,
      targetValue: target.value ?? null,
      recipients,
      successCount,
      failureCount,
    });
}

export function stats() {
  const total = db.prepare('SELECT COUNT(*) AS n FROM devices').get().n;
  const withLogin = db
    .prepare("SELECT COUNT(*) AS n FROM devices WHERE client_login IS NOT NULL AND client_login != ''")
    .get().n;
  const byPlatform = db
    .prepare('SELECT platform, COUNT(*) AS n FROM devices GROUP BY platform')
    .all();
  return { total, withLogin, byPlatform };
}

export function recentBroadcasts(limit = 20) {
  return db.prepare('SELECT * FROM broadcasts ORDER BY id DESC LIMIT ?').all(limit);
}
