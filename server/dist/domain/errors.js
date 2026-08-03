export class AppError extends Error {
    message;
    statusCode;
    details;
    constructor(message, statusCode = 500, details) {
        super(message);
        this.message = message;
        this.statusCode = statusCode;
        this.details = details;
        this.name = this.constructor.name;
        Error.captureStackTrace(this, this.constructor);
    }
}
export class ValidationError extends AppError {
    constructor(message, details) {
        super(message, 400, details);
    }
}
export class UnauthorizedError extends AppError {
    constructor(message = 'Доступ запрещён') {
        super(message, 401);
    }
}
export class NotFoundError extends AppError {
    constructor(message = 'Ресурс не найден') {
        super(message, 404);
    }
}
