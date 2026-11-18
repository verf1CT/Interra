// Сервис взаимодействия с биллингом провайдера «Интерра» (UTM5 / собственный API)

export class BillingService {
  constructor(options = {}) {
    this.apiUrl = options.apiUrl || process.env.BILLING_API_URL || '';
    this.apiToken = options.apiToken || process.env.BILLING_API_TOKEN || '';
    this.isMock = !this.apiUrl;
  }

  // Поиск абонента по номеру телефона
  async findByPhone(phone) {
    const cleanPhone = phone.replace(/\D/g, '');
    if (!this.isMock) {
      const res = await fetch(`${this.apiUrl}/billing/find_by_phone?phone=${encodeURIComponent(cleanPhone)}`, {
        headers: { Authorization: `Bearer ${this.apiToken}` }
      });
      if (!res.ok) throw new Error(`Billing findByPhone failed: ${res.status}`);
      return await res.json();
    }

    // Realistic Mock на основе реальной карточки абонента Интерры
    return {
      epay: '504600', // Номер лицевого счета (ЕПАЙ / электронный счет)
      contract_id: '504600',
      account_id: '10099',
      username: '10099call',
      full_name: 'Михайлов Александр',
      user_city: 'Первоуральск',
      address: 'г. Первоуральск, ул. Трубников 24',
      balance_amount: '650.00',
      tariff_name: 'Комфорт 200 + ТВ',
      tariff_price: '550.00',
      addon_price: '100.00',
      switch_ip: '94.190.43.32',
      switch_port: 'Fa0/12'
    };
  }

  // Детализация начислений за текущий расчетный период по ЕПАЙ
  async getInvoiceDetails(epay) {
    if (!this.isMock) {
      const res = await fetch(`${this.apiUrl}/billing/invoice_details?epay=${encodeURIComponent(epay)}`, {
        headers: { Authorization: `Bearer ${this.apiToken}` }
      });
      if (!res.ok) throw new Error(`Billing getInvoiceDetails failed: ${res.status}`);
      return await res.json();
    }

    return {
      epay: epay || '504600',
      contract_id: epay || '504600',
      tariff_name: 'Комфорт 200 + ТВ',
      tariff_price: '550',
      addon_price: '100',
      balance_amount: '650'
    };
  }

  // Фоновая диагностика линии (SNMP / TDR-тест порта коммутатора и аварийная база)
  async checkLineDiagnostics(phone, forceBranch = null) {
    if (!this.isMock) {
      const res = await fetch(`${this.apiUrl}/billing/line_diagnostics?phone=${encodeURIComponent(phone)}`, {
        headers: { Authorization: `Bearer ${this.apiToken}` }
      });
      if (!res.ok) throw new Error(`Billing checkLineDiagnostics failed: ${res.status}`);
      return await res.json();
    }

    // Для гибкого тестирования можно симулировать разные исходы
    if (forceBranch === 'alarm' || phone.endsWith('111')) {
      const finishTime = new Date(Date.now() + 2 * 60 * 60 * 1000);
      return {
        status: 'ALARM',
        has_incident: true,
        incident_end_time: `${finishTime.getHours()}:${String(finishTime.getMinutes()).padStart(2, '0')}`,
        port_status: 'down',
        description: 'Массовая авария: обрыв оптического кабеля Екб-Первоуральск'
      };
    }

    if (forceBranch === 'cable_cut' || phone.endsWith('222')) {
      return {
        status: 'CABLE_CUT',
        has_incident: false,
        port_status: 'down',
        tdr_result: 'Open at 14m',
        description: 'Физический обрыв витой пары на расстоянии 14 метров от домового свитча'
      };
    }

    // Default: Порт активен, линк есть (проблема в сессии абонента или роутере)
    return {
      status: 'PORT_UP',
      has_incident: false,
      port_status: 'up',
      description: 'Порт коммутатора активен. Требуется проверка клиентского роутера / сброс сессии'
    };
  }

  // Инженерный сброс порта коммутатора и сброс сессии в биллинге (RADIUS / DHCP)
  async restartSwitchPort(epay) {
    if (!this.isMock) {
      const res = await fetch(`${this.apiUrl}/network/switch_port_restart`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiToken}`
        },
        body: JSON.stringify({ epay })
      });
      if (!res.ok) throw new Error(`Network restartSwitchPort failed: ${res.status}`);
      return await res.json();
    }

    return {
      success: true,
      port_reset: true,
      session_cleared: true,
      timestamp: new Date().toISOString()
    };
  }

  // Список тарифов по городам
  async getTariffs(city = 'Первоуральск') {
    const tariffMap = {
      'Первоуральск': [
        { name: 'Старт 100 Мбит/с', price: '450 руб/мес' },
        { name: 'Комфорт 200 Мбит/с + ТВ (180 каналов)', price: '550 руб/мес' },
        { name: 'Максимум 500 Мбит/с + ТВ + KION', price: '750 руб/мес' }
      ],
      'Ревда': [
        { name: 'Ревда Оптима 100 Мбит/с', price: '490 руб/мес' },
        { name: 'Ревда Драйв 300 Мбит/с + ТВ', price: '650 руб/мес' }
      ],
      'Екатеринбург': [
        { name: 'ЕКБ Базовый 100 Мбит/с', price: '500 руб/мес' },
        { name: 'ЕКБ Гигабит 500 Мбит/с + ТВ', price: '790 руб/мес' }
      ]
    };

    return tariffMap[city] || [
      { name: 'Базовый 100 Мбит/с', price: '490 руб/мес' },
      { name: 'Скоростной 200 Мбит/с + ТВ', price: '590 руб/мес' },
      { name: 'Ультра 500 Мбит/с', price: '750 руб/мес' }
    ];
  }
}
