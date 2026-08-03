import { z } from 'zod';

export const TargetSchema = z
  .object({
    type: z.enum(['all', 'segment', 'login']),
    value: z.string().optional(),
  })
  .superRefine((data, ctx) => {
    if ((data.type === 'segment' || data.type === 'login') && !data.value) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'для target.type "segment" или "login" поле target.value обязательно',
        path: ['value'],
      });
    }
  });

const HttpsUrl = z
  .string()
  .url('Должна быть валидной URL ссылкой')
  .superRefine((val, ctx) => {
    if (!val.toLowerCase().startsWith('https://')) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'Ссылка должна начинаться с https://',
      });
    }
  });

export const RegisterDeviceSchema = z.object({
  token: z.string().min(1, 'token обязателен'),
  clientLogin: z.string().nullable().optional(),
  platform: z.string().nullable().optional(),
  appVersion: z.string().nullable().optional(),
  segments: z.array(z.string()).optional(),
  prefs: z.record(z.string(), z.unknown()).optional(),
});

export const UnregisterDeviceSchema = z.object({
  token: z.string().min(1, 'token обязателен'),
});

export const BroadcastSchema = z.object({
  title: z.string().min(1, 'title обязателен'),
  body: z.string().min(1, 'body обязателен'),
  target: TargetSchema,
  data: z.record(z.string(), z.unknown()).optional(),
  imageUrl: HttpsUrl.nullable().optional(),
  link: HttpsUrl.nullable().optional(),
  sendAt: z.string().optional(),
});

export const OpenedEventSchema = z.object({
  bid: z.coerce.number().int().positive('bid обязателен и должен быть > 0'),
});

export type RegisterDeviceDto = z.infer<typeof RegisterDeviceSchema>;
export type UnregisterDeviceDto = z.infer<typeof UnregisterDeviceSchema>;
export type BroadcastDto = z.infer<typeof BroadcastSchema>;
export type OpenedEventDto = z.infer<typeof OpenedEventSchema>;
export type TargetDto = z.infer<typeof TargetSchema>;
