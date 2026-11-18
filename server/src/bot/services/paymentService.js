// Сервис генерации ссылок СБП (Система быстрых платежей) и WebApp оплаты

export class PaymentService {
  constructor(options = {}) {
    this.sbpEndpoint = options.sbpEndpoint || process.env.SBP_API_URL || '';
  }

  // Генерация динамической ссылки для мгновенного перехода в банковское приложение по СБП
  generateSbpLink(contractId, amount) {
    const cleanAmount = (amount || '0').replace(',', '.');
    const encodedDesc = encodeURIComponent(`Оплата услуг Интерра, договор ${contractId}`);

    // Стандартный payload для СБП QR / Deeplink или редиректа на страницу оплаты
    return `https://interra.ru/pay?contract=${encodeURIComponent(contractId)}&sum=${cleanAmount}&source=bot_sbp`;
  }
}
