import path from 'node:path';
import express from 'express';
import { config } from './config.js';
import './db.js';
import { devicesRouter } from './routes/devices.js';
import { adminRouter } from './routes/admin.js';

const app = express();
app.use(express.json());

// Статика админ-панели
app.use(express.static(path.join(config.serverRoot, 'public')));

app.get('/health', (req, res) => res.json({ ok: true }));

app.use('/api/devices', devicesRouter);
app.use('/api/admin', adminRouter);

app.use((err, req, res, next) => {
  console.error('[error]', err);
  res.status(500).json({ error: 'internal error' });
});

app.listen(config.port, () => {
  console.log(`[server] ЛК Интерра backend слушает http://localhost:${config.port}`);
  console.log(`[server] Админ-панель: http://localhost:${config.port}/admin.html`);
});
