import { db } from '../db/connection.js';
export class BroadcastRepository {
    logBroadcast(params) {
        const { title, body, data, target, recipients, successCount, failureCount } = params;
        return db
            .prepare(`INSERT INTO broadcasts (title, body, data, target_type, target_value, recipients, success_count, failure_count)
         VALUES (@title, @body, @data, @targetType, @targetValue, @recipients, @successCount, @failureCount)`)
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
    updateBroadcastResult(id, successCount, failureCount) {
        return db
            .prepare('UPDATE broadcasts SET success_count = ?, failure_count = ? WHERE id = ?')
            .run(successCount, failureCount, id);
    }
    incrementOpens(id) {
        return db.prepare('UPDATE broadcasts SET opens = opens + 1 WHERE id = ?').run(id);
    }
    getRecentBroadcasts(limit = 20) {
        return db.prepare('SELECT * FROM broadcasts ORDER BY id DESC LIMIT ?').all(limit);
    }
    getBroadcastStats() {
        return db
            .prepare(`SELECT COUNT(*)                       AS total,
                COALESCE(SUM(recipients), 0)    AS recipients,
                COALESCE(SUM(success_count), 0) AS success,
                COALESCE(SUM(failure_count), 0) AS failure,
                COALESCE(SUM(opens), 0)         AS opens
         FROM broadcasts`)
            .get();
    }
    createScheduled(params) {
        const { title, body, data, imageUrl, link, target, sendAt } = params;
        return db
            .prepare(`INSERT INTO scheduled_broadcasts
           (title, body, data, image_url, link, target_type, target_value, send_at)
         VALUES (@title, @body, @data, @imageUrl, @link, @targetType, @targetValue, @sendAt)`)
            .run({
            title,
            body,
            data: JSON.stringify(data ?? {}),
            imageUrl: imageUrl ?? null,
            link: link ?? null,
            targetType: target.type,
            targetValue: target.value ?? null,
            sendAt,
        });
    }
    listScheduled() {
        return db
            .prepare("SELECT * FROM scheduled_broadcasts WHERE status = 'pending' ORDER BY send_at ASC")
            .all();
    }
    cancelScheduled(id) {
        return db
            .prepare("UPDATE scheduled_broadcasts SET status = 'canceled' WHERE id = ? AND status = 'pending'")
            .run(id);
    }
    dueScheduled(nowIso) {
        return db
            .prepare("SELECT * FROM scheduled_broadcasts WHERE status = 'pending' AND send_at <= ? ORDER BY send_at ASC")
            .all(nowIso);
    }
    markScheduledSent(id) {
        return db.prepare("UPDATE scheduled_broadcasts SET status = 'sent' WHERE id = ?").run(id);
    }
}
