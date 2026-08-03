import { Express, Request, Response } from 'express';
import { apiReference } from '@scalar/express-api-reference';

export const openApiDocument = {
  openapi: '3.1.0',
  info: {
    title: 'ЛК Интерра — Push Server API',
    version: '0.2.0',
    description:
      'Enterprise REST API сервера рассылки уведомлений и управления устройствами абонентов интернет-провайдера «Интерра».',
  },
  servers: [
    {
      url: 'http://localhost:8080',
      description: 'Локальное окружение разработки',
    },
    {
      url: 'https://push.interra.ru',
      description: 'Продакшн сервер',
    },
  ],
  components: {
    securitySchemes: {
      BearerAuth: {
        type: 'http',
        scheme: 'bearer',
        bearerFormat: 'Token',
        description: 'Токен администратора (ADMIN_TOKEN из .env)',
      },
    },
    schemas: {
      DeviceRegisterInput: {
        type: 'object',
        required: ['token'],
        properties: {
          token: { type: 'string', description: 'FCM push-токен устройства' },
          clientLogin: { type: 'string', nullable: true, description: 'Логин абонента в UTM5' },
          platform: { type: 'string', nullable: true, example: 'ios' },
          appVersion: { type: 'string', nullable: true, example: '1.0.0' },
          segments: { type: 'array', items: { type: 'string' }, example: ['beta', 'vip'] },
          prefs: { type: 'object', description: 'Пользовательские настройки' },
        },
      },
      DeviceUnregisterInput: {
        type: 'object',
        required: ['token'],
        properties: {
          token: { type: 'string', description: 'FCM push-токен устройства' },
        },
      },
      BroadcastInput: {
        type: 'object',
        required: ['title', 'body', 'target'],
        properties: {
          title: { type: 'string', example: 'Напоминание об оплате' },
          body: { type: 'string', example: 'Уважаемый абонент, до конца месяца осталось 3 дня.' },
          target: {
            type: 'object',
            required: ['type'],
            properties: {
              type: { type: 'string', enum: ['all', 'segment', 'login'] },
              value: { type: 'string', description: 'Обязательно для segment и login' },
            },
          },
          imageUrl: { type: 'string', format: 'uri', example: 'https://push.interra.ru/banner.jpg' },
          link: { type: 'string', format: 'uri', example: 'https://interra.ru/pay' },
          sendAt: { type: 'string', format: 'date-time', description: 'Для отложенных рассылок в ISO UTC' },
        },
      },
      OpenedEventInput: {
        type: 'object',
        required: ['bid'],
        properties: {
          bid: { type: 'integer', example: 42, description: 'ID рассылки (broadcastId)' },
        },
      },
    },
  },
  paths: {
    '/healthz': {
      get: {
        summary: 'Liveness Проба',
        description: 'Возвращает статус доступности HTTP-сервера и uptime.',
        responses: {
          '200': { description: 'Сервер работает' },
        },
      },
    },
    '/readyz': {
      get: {
        summary: 'Readiness Проба',
        description: 'Проверяет активное подключение к SQLite базе данных.',
        responses: {
          '200': { description: 'Сервер и БД полностью готовы' },
          '503': { description: 'БД недоступна' },
        },
      },
    },
    '/metrics': {
      get: {
        summary: 'Prometheus Метрики',
        description: 'Метрики в формате Prometheus для мониторинга латентности и статистики рассылок.',
        responses: {
          '200': { description: 'Текст в формате Prometheus metrics' },
        },
      },
    },
    '/api/devices/register': {
      post: {
        summary: 'Регистрация устройства',
        description: 'Приложение вызывает этот метод при старте или обновлении FCM-токена.',
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: { $ref: '#/components/schemas/DeviceRegisterInput' },
            },
          },
        },
        responses: {
          '200': { description: 'Устройство успешно зарегистрировано' },
          '400': { description: 'Ошибка валидации данных' },
        },
      },
    },
    '/api/devices/unregister': {
      post: {
        summary: 'Удаление устройства',
        description: 'Удаляет токен при выходе абонента из профиля.',
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: { $ref: '#/components/schemas/DeviceUnregisterInput' },
            },
          },
        },
        responses: {
          '200': { description: 'Токен удалён' },
        },
      },
    },
    '/api/events/opened': {
      post: {
        summary: 'Отметка открытия пуша',
        description: 'Фиксирует нажатие пользователя по уведомлению для подсчёта Open-Rate/CTR.',
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: { $ref: '#/components/schemas/OpenedEventInput' },
            },
          },
        },
        responses: {
          '200': { description: 'Открытие зафиксировано' },
        },
      },
    },
    '/api/admin/stats': {
      get: {
        summary: 'Статистика сервера и аналитика',
        security: [{ BearerAuth: [] }],
        responses: {
          '200': { description: 'Сводка по устройствам, рассылкам и FCM' },
          '401': { description: 'Неверный токен администратора' },
        },
      },
    },
    '/api/admin/broadcast': {
      post: {
        summary: 'Отправка / Планирование рассылки',
        security: [{ BearerAuth: [] }],
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: { $ref: '#/components/schemas/BroadcastInput' },
            },
          },
        },
        responses: {
          '200': { description: 'Рассылка отправлена или запланирована' },
          '400': { description: 'Ошибка валидации' },
          '401': { description: 'Доступ запрещён' },
        },
      },
    },
    '/api/admin/scheduled': {
      get: {
        summary: 'Список отложенных рассылок',
        security: [{ BearerAuth: [] }],
        responses: {
          '200': { description: 'Массив ожидающих отправки рассылок' },
        },
      },
    },
    '/api/admin/scheduled/{id}/cancel': {
      post: {
        summary: 'Отмена отложенной рассылки',
        security: [{ BearerAuth: [] }],
        parameters: [
          {
            name: 'id',
            in: 'path',
            required: true,
            schema: { type: 'integer' },
          },
        ],
        responses: {
          '200': { description: 'Рассылка отменена' },
        },
      },
    },
  },
};

export function setupOpenApi(app: Express) {
  app.get('/openapi.json', (_req: Request, res: Response) => {
    res.json(openApiDocument);
  });

  app.use(
    '/docs',
    apiReference({
      spec: {
        url: '/openapi.json',
      },
      theme: 'purple',
    })
  );
}
