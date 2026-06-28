import 'dotenv/config';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverRoot = path.resolve(__dirname, '..');

function resolveFromRoot(p, fallback) {
  const value = p || fallback;
  return path.isAbsolute(value) ? value : path.resolve(serverRoot, value);
}

export const config = {
  port: Number(process.env.PORT) || 8080,
  adminToken: process.env.ADMIN_TOKEN || '',
  dbPath: resolveFromRoot(process.env.DB_PATH, './data/interra.sqlite'),
  firebaseServiceAccount: process.env.FIREBASE_SERVICE_ACCOUNT
    ? resolveFromRoot(process.env.FIREBASE_SERVICE_ACCOUNT)
    : '',
  serverRoot,
};

if (!config.adminToken) {
  console.warn(
    '[config] ADMIN_TOKEN не задан — админ-эндпоинты будут отклонять все запросы. ' +
      'Скопируйте .env.example в .env и задайте ADMIN_TOKEN.'
  );
}
