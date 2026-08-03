import { Request, Response, NextFunction } from 'express';
import { ZodSchema, ZodError } from 'zod';
import { ValidationError } from '../domain/errors.js';

export function validateBody(schema: ZodSchema) {
  return (req: Request, _res: Response, next: NextFunction) => {
    try {
      req.body = schema.parse(req.body);
      next();
    } catch (err) {
      if (err instanceof ZodError) {
        const issue = err.issues[0];
        const msg = issue ? `${issue.path.join('.')}: ${issue.message}` : 'Ошибка валидации данных';
        return next(new ValidationError(msg, err.issues));
      }
      next(err);
    }
  };
}
