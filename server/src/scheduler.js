import { dueScheduled, markScheduledSent } from './db.js';
import { runBroadcast } from './broadcast.js';

const TICK_MS = Number(process.env.SCHEDULER_TICK_MS) || 30_000;

async function tick() {
  let due;
  try {
    due = dueScheduled(new Date().toISOString());
  } catch (e) {
    console.error('[scheduler] выборка запланированных упала:', e);
    return;
  }
  for (const row of due) {
    // помечаем отправленной СРАЗУ, чтобы пересекающиеся тики не отправили дважды
    markScheduledSent(row.id);
    try {
      const data = JSON.parse(row.data || '{}');
      const r = await runBroadcast({
        title: row.title,
        body: row.body,
        data,
        imageUrl: row.image_url || undefined,
        link: row.link || undefined,
        target: { type: row.target_type, value: row.target_value || undefined },
      });
      console.log(
        `[scheduler] рассылка #${row.id} "${row.title}" → ${r.successCount}/${r.recipients}`
      );
    } catch (e) {
      console.error(`[scheduler] ошибка рассылки #${row.id}:`, e);
    }
  }
}

/** запускает фоновый опрос запланированных рассылок. */
export function startScheduler() {
  tick(); // сразу подберём просроченные при старте
  const timer = setInterval(tick, TICK_MS);
  timer.unref?.();
}
