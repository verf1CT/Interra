import fs from 'node:fs';
import path from 'node:path';
import Database from 'better-sqlite3';
import { config } from '../config/env.js';
import { logger } from '../infrastructure/logger.js';
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

  CREATE TABLE IF NOT EXISTS scheduled_broadcasts (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    title        TEXT NOT NULL,
    body         TEXT NOT NULL,
    data         TEXT NOT NULL DEFAULT '{}',
    image_url    TEXT,
    link         TEXT,
    target_type  TEXT NOT NULL,
    target_value TEXT,
    send_at      TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'pending',
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_sched_due ON scheduled_broadcasts(status, send_at);
`);
// Migration for opens column
try {
    const cols = db.prepare('PRAGMA table_info(broadcasts)').all();
    if (!cols.some((c) => c.name === 'opens')) {
        db.exec('ALTER TABLE broadcasts ADD COLUMN opens INTEGER NOT NULL DEFAULT 0');
        logger.info('Migration: added opens column to broadcasts table');
    }
}
catch (err) {
    logger.error({ err }, 'Migration failed');
}
