import { db } from '../db/connection.js';

export interface IncidentRow {
  id: number;
  title: string;
  description: string | null;
  type: 'incident' | 'planned_work';
  status: 'active' | 'resolved';
  affected_area: string | null;
  created_at: string;
  resolved_at: string | null;
}

export class IncidentRepository {
  create(params: { title: string; description?: string; type?: string; affectedArea?: string }): { id: number | bigint } {
    const { title, description, type, affectedArea } = params;
    const result = db.prepare(
      `INSERT INTO incidents (title, description, type, affected_area)
       VALUES (@title, @description, @type, @affectedArea)`
    ).run({
      title,
      description: description ?? null,
      type: type ?? 'incident',
      affectedArea: affectedArea ?? null,
    });
    return { id: result.lastInsertRowid };
  }

  resolve(id: number): { changes: number } {
    const result = db.prepare(
      `UPDATE incidents SET status = 'resolved', resolved_at = datetime('now') WHERE id = ? AND status = 'active'`
    ).run(id);
    return { changes: result.changes };
  }

  getById(id: number): IncidentRow | undefined {
    return db.prepare('SELECT * FROM incidents WHERE id = ?').get(id) as IncidentRow | undefined;
  }

  listActive(): IncidentRow[] {
    return db.prepare("SELECT * FROM incidents WHERE status = 'active' ORDER BY created_at DESC").all() as IncidentRow[];
  }

  listRecent(limit = 20): IncidentRow[] {
    return db.prepare('SELECT * FROM incidents ORDER BY created_at DESC LIMIT ?').all(limit) as IncidentRow[];
  }
}
