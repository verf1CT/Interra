import 'dotenv/config';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const serverRoot = path.resolve(__dirname, '../..');
function resolveFromRoot(p, fallback) {
    const value = p || fallback;
    return path.isAbsolute(value) ? value : path.resolve(serverRoot, value);
}
const envSchema = z.object({
    PORT: z.coerce.number().default(8080),
    ADMIN_TOKEN: z.string().default(''),
    DB_PATH: z.string().optional(),
    FIREBASE_SERVICE_ACCOUNT: z.string().optional(),
    NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
    ALLOWED_ORIGINS: z.string().default('*'),
});
const parsed = envSchema.safeParse(process.env);
if (!parsed.success) {
    console.error('❌ Invalid environment variables:', parsed.error.format());
    throw new Error('Invalid environment variables');
}
const envData = parsed.data;
export const config = {
    port: envData.PORT,
    adminToken: envData.ADMIN_TOKEN,
    dbPath: resolveFromRoot(envData.DB_PATH, './data/interra.sqlite'),
    firebaseServiceAccount: envData.FIREBASE_SERVICE_ACCOUNT
        ? resolveFromRoot(envData.FIREBASE_SERVICE_ACCOUNT, '')
        : '',
    nodeEnv: envData.NODE_ENV,
    allowedOrigins: envData.ALLOWED_ORIGINS,
    serverRoot,
};
if (!config.adminToken && config.nodeEnv !== 'test') {
    console.warn('⚠️ [config] ADMIN_TOKEN не задан — админ-эндпоинты будут отклонять все запросы. ' +
        'Скопируйте .env.example в .env и задайте ADMIN_TOKEN.');
}
