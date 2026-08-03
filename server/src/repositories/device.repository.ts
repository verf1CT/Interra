import { db } from '../db/connection.js';

export interface DeviceRow {
  id: number;
  token: string;
  client_login: string | null;
  platform: string | null;
  app_version: string | null;
  segments: string;
  prefs: string;
  created_at: string;
  updated_at: string;
}

export interface UpsertDeviceParams {
  token: string;
  clientLogin?: string | null;
  platform?: string | null;
  appVersion?: string | null;
  segments?: string[];
  prefs?: Record<string, unknown>;
}

export class DeviceRepository {
  upsert(params: UpsertDeviceParams): DeviceRow {
    const { token, clientLogin, platform, appVersion, segments, prefs } = params;
    const existing = db.prepare('SELECT * FROM devices WHERE token = ?').get(token) as DeviceRow | undefined;

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

    return db.prepare('SELECT * FROM devices WHERE token = ?').get(token) as DeviceRow;
  }

  deleteByToken(token: string) {
    return db.prepare('DELETE FROM devices WHERE token = ?').run(token);
  }

  selectTokensByTarget(target: { type: 'all' | 'segment' | 'login'; value?: string }): string[] {
    if (target.type === 'all') {
      const rows = db.prepare('SELECT token FROM devices').all() as { token: string }[];
      return rows.map((r) => r.token);
    }
    if (target.type === 'login' && target.value) {
      const rows = db
        .prepare('SELECT token FROM devices WHERE client_login = ?')
        .all(target.value) as { token: string }[];
      return rows.map((r) => r.token);
    }
    if (target.type === 'segment' && target.value) {
      const rows = db.prepare('SELECT token, segments FROM devices').all() as {
        token: string;
        segments: string;
      }[];
      return rows
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

  getStats() {
    const total = (db.prepare('SELECT COUNT(*) AS n FROM devices').get() as { n: number }).n;
    const withLogin = (
      db
        .prepare("SELECT COUNT(*) AS n FROM devices WHERE client_login IS NOT NULL AND client_login != ''")
        .get() as { n: number }
    ).n;
    const byPlatform = db
      .prepare('SELECT platform, COUNT(*) AS n FROM devices GROUP BY platform')
      .all() as { platform: string | null; n: number }[];

    return { total, withLogin, byPlatform };
  }
}
