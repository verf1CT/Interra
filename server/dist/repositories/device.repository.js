import { db } from '../db/connection.js';
export class DeviceRepository {
    upsert(params) {
        const { token, clientLogin, platform, appVersion, segments, prefs } = params;
        const existing = db.prepare('SELECT * FROM devices WHERE token = ?').get(token);
        if (existing) {
            db.prepare(`UPDATE devices SET
           client_login = COALESCE(@clientLogin, client_login),
           platform     = COALESCE(@platform, platform),
           app_version  = COALESCE(@appVersion, app_version),
           segments     = COALESCE(@segments, segments),
           prefs        = COALESCE(@prefs, prefs),
           updated_at   = datetime('now')
         WHERE token = @token`).run({
                token,
                clientLogin: clientLogin ?? null,
                platform: platform ?? null,
                appVersion: appVersion ?? null,
                segments: segments ? JSON.stringify(segments) : null,
                prefs: prefs ? JSON.stringify(prefs) : null,
            });
        }
        else {
            db.prepare(`INSERT INTO devices (token, client_login, platform, app_version, segments, prefs)
         VALUES (@token, @clientLogin, @platform, @appVersion, @segments, @prefs)`).run({
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
    deleteByToken(token) {
        return db.prepare('DELETE FROM devices WHERE token = ?').run(token);
    }
    selectTokensByTarget(target) {
        if (target.type === 'all') {
            const rows = db.prepare('SELECT token FROM devices').all();
            return rows.map((r) => r.token);
        }
        if (target.type === 'login' && target.value) {
            const rows = db
                .prepare('SELECT token FROM devices WHERE client_login = ?')
                .all(target.value);
            return rows.map((r) => r.token);
        }
        if (target.type === 'segment' && target.value) {
            const rows = db.prepare('SELECT token, segments FROM devices').all();
            return rows
                .filter((r) => {
                try {
                    return JSON.parse(r.segments).includes(target.value);
                }
                catch {
                    return false;
                }
            })
                .map((r) => r.token);
        }
        return [];
    }
    getStats() {
        const total = db.prepare('SELECT COUNT(*) AS n FROM devices').get().n;
        const withLogin = db
            .prepare("SELECT COUNT(*) AS n FROM devices WHERE client_login IS NOT NULL AND client_login != ''")
            .get().n;
        const byPlatform = db
            .prepare('SELECT platform, COUNT(*) AS n FROM devices GROUP BY platform')
            .all();
        return { total, withLogin, byPlatform };
    }
}
