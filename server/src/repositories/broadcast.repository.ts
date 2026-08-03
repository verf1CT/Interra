import { db } from '../db/connection.js';

export interface BroadcastRow {
  id: number;
  title: string;
  body: string;
  data: string;
  target_type: string;
  target_value: string | null;
  recipients: number;
  success_count: number;
  failure_count: number;
  opens: number;
  created_at: string;
}

export interface ScheduledBroadcastRow {
  id: number;
  title: string;
  body: string;
  data: string;
  image_url: string | null;
  link: string | null;
  target_type: string;
  target_value: string | null;
  send_at: string;
  status: 'pending' | 'sent' | 'canceled';
  created_at: string;
}

export class BroadcastRepository {
  logBroadcast(params: {
    title: string;
    body: string;
    data?: Record<string, unknown>;
    target: { type: string; value?: string };
    recipients: number;
    successCount: number;
    failureCount: number;
  }) {
    const { title, body, data, target, recipients, successCount, failureCount } = params;
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

  updateBroadcastResult(id: number | bigint, successCount: number, failureCount: number) {
    return db
      .prepare('UPDATE broadcasts SET success_count = ?, failure_count = ? WHERE id = ?')
      .run(successCount, failureCount, id);
  }

  incrementOpens(id: number) {
    return db.prepare('UPDATE broadcasts SET opens = opens + 1 WHERE id = ?').run(id);
  }

  getRecentBroadcasts(limit = 20): BroadcastRow[] {
    return db.prepare('SELECT * FROM broadcasts ORDER BY id DESC LIMIT ?').all(limit) as BroadcastRow[];
  }

  getBroadcastStats() {
    return db
      .prepare(
        `SELECT COUNT(*)                       AS total,
                COALESCE(SUM(recipients), 0)    AS recipients,
                COALESCE(SUM(success_count), 0) AS success,
                COALESCE(SUM(failure_count), 0) AS failure,
                COALESCE(SUM(opens), 0)         AS opens
         FROM broadcasts`
      )
      .get() as { total: number; recipients: number; success: number; failure: number; opens: number };
  }

  createScheduled(params: {
    title: string;
    body: string;
    data?: Record<string, unknown>;
    imageUrl?: string | null;
    link?: string | null;
    target: { type: string; value?: string };
    sendAt: string;
  }) {
    const { title, body, data, imageUrl, link, target, sendAt } = params;
    return db
      .prepare(
        `INSERT INTO scheduled_broadcasts
           (title, body, data, image_url, link, target_type, target_value, send_at)
         VALUES (@title, @body, @data, @imageUrl, @link, @targetType, @targetValue, @sendAt)`
      )
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

  listScheduled(): ScheduledBroadcastRow[] {
    return db
      .prepare("SELECT * FROM scheduled_broadcasts WHERE status = 'pending' ORDER BY send_at ASC")
      .all() as ScheduledBroadcastRow[];
  }

  cancelScheduled(id: number) {
    return db
      .prepare("UPDATE scheduled_broadcasts SET status = 'canceled' WHERE id = ? AND status = 'pending'")
      .run(id);
  }

  dueScheduled(nowIso: string): ScheduledBroadcastRow[] {
    return db
      .prepare("SELECT * FROM scheduled_broadcasts WHERE status = 'pending' AND send_at <= ? ORDER BY send_at ASC")
      .all(nowIso) as ScheduledBroadcastRow[];
  }

  markScheduledSent(id: number) {
    return db.prepare("UPDATE scheduled_broadcasts SET status = 'sent' WHERE id = ?").run(id);
  }
}
