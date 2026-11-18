import { SCENARIO } from './scenarioData.js';
import { BillingService } from './services/billingService.js';
import { CrmService } from './services/crmService.js';
import { PaymentService } from './services/paymentService.js';

export class BotEngine {
  constructor(options = {}) {
    this.scenario = options.scenario || SCENARIO;
    this.billing = options.billing || new BillingService(options.billingConfig);
    this.crm = options.crm || new CrmService(options.crmConfig);
    this.payment = options.payment || new PaymentService(options.paymentConfig);
    this.sessions = new Map(); // key: userId -> session state
  }

  // Получить или инициализировать сессию пользователя
  getSession(userId) {
    if (!this.sessions.has(userId)) {
      this.sessions.set(userId, {
        userId,
        currentStep: 'START_01',
        history: [],
        inOperatorMode: false,
        operatorQueue: null,
        variables: {
          epay: '504600', // Номер лицевого счёта ЕПАЙ (основной идентификатор в Интерре)
          contract_id: '504600', // Для обратной совместимости
          tariff_name: 'Комфорт 200 + ТВ',
          tariff_price: '550',
          addon_price: '100',
          balance_amount: '650',
          user_city: 'Первоуральск',
          user_phone: '',
          lead_address: '',
          lead_service: '',
          lead_name: '',
          lead_id: '',
          ticket_id: '49281',
          ticket_type: 'Ремонт линии',
          ticket_status: 'В очереди диспетчера',
          master_time: 'Согласуется диспетчером',
          master_name: 'Дежурная бригада',
          master_phone: '+7 (3439) 66-00-00',
          ticket_issue: 'Диагностика кабельной линии / сброс сессии',
          incident_end_time: '14:30',
          sbp_payment_url: 'https://interra.ru/pay?contract=504600&sum=650&source=bot_sbp',
          tariffs_list: ''
        }
      });
    }
    return this.sessions.get(userId);
  }

  // Сброс сессии
  resetSession(userId) {
    this.sessions.delete(userId);
    return this.getSession(userId);
  }

  // Старт диалога (команда /start)
  async handleStart(userId) {
    const session = this.resetSession(userId);
    return await this.renderStep(session, 'START_01');
  }

  // Обработка клика по кнопке
  async handleButtonClick(userId, targetStepId, buttonValue = null) {
    const session = this.getSession(userId);

    // Если пользователь был у оператора и нажал "Вернуться к боту"
    if (targetStepId === 'START_01' || targetStepId === 'CURRENT_01') {
      session.inOperatorMode = false;
      session.operatorQueue = null;
    }

    if (buttonValue) {
      if (session.currentStep === 'TAR_CITY' || targetStepId === 'TAR_CITY_SELECTED') {
        session.variables.user_city = buttonValue;
      } else if (session.currentStep === 'CONN_02') {
        session.variables.lead_service = buttonValue;
      } else if (session.currentStep === 'REQ_RESCHEDULE') {
        session.variables.selected_slot = buttonValue;
      }
    }

    return await this.transitionTo(session, targetStepId, { buttonValue });
  }

  // Обработка текстового ввода пользователя
  async handleTextInput(userId, text) {
    const session = this.getSession(userId);
    const trimmed = (text || '').trim();

    // Запись в историю
    session.history.push({ from: 'user', text: trimmed, timestamp: new Date().toISOString() });

    // Если активен режим общения с оператором
    if (session.inOperatorMode) {
      // Проверка на команду выхода из диалога с оператором
      if (trimmed.toLowerCase().includes('меню') || trimmed.toLowerCase().includes('выход') || trimmed === '/start') {
        session.inOperatorMode = false;
        session.operatorQueue = null;
        return await this.renderStep(session, 'CURRENT_01');
      }

      // Отправка в CRM / Helpdesk шлюз
      await this.crm.routeToOperator({
        queue: session.operatorQueue || 'support',
        userId,
        contractId: session.variables.epay || session.variables.contract_id,
        history: session.history
      });

      return {
        stepId: 'IN_OPERATOR_DIALOG',
        text: 'Ваше сообщение передано оператору. Специалист уже читает переписку и ответит в этом чате.',
        buttons: [
          { text: '↩️ Завершить диалог и вернуться в меню', next: 'CURRENT_01' }
        ]
      };
    }

    const currentStepConfig = this.scenario[session.currentStep] || {};

    // 1. Ввод телефона для сетевой диагностики (NET_01)
    if (session.currentStep === 'NET_01') {
      const cleanPhone = trimmed.replace(/[^\d+]/g, '');
      if (cleanPhone.length < 10) {
        return {
          stepId: 'NET_01',
          text: '⚠️ Пожалуйста, введите корректный номер телефона (10 или 11 цифр, например: +79991234567):',
          buttons: [
            { text: '↩️ Назад в меню', next: 'CURRENT_01' }
          ]
        };
      }
      session.variables.user_phone = cleanPhone;
      return await this.transitionTo(session, 'NET_02');
    }

    // 2. Поиск заявки мастера (REQ_01)
    if (session.currentStep === 'REQ_01') {
      session.variables.search_contact = trimmed;
      return await this.transitionTo(session, 'REQ_CHECK');
    }

    // 3. Выбор произвольной даты визита мастера (REQ_CALENDAR)
    if (session.currentStep === 'REQ_CALENDAR') {
      session.variables.master_time = trimmed;
      return await this.transitionTo(session, 'REQ_RESCHEDULE_DONE', { manualSlot: trimmed });
    }

    // 4. Ввод адреса для проверки подключения (CONN_01)
    if (session.currentStep === 'CONN_01') {
      session.variables.lead_address = trimmed;
      return await this.transitionTo(session, 'CONN_02');
    }

    // 5. Экспресс-заявка в 1 шаг (CONN_DIRECT)
    if (session.currentStep === 'CONN_DIRECT') {
      session.variables.lead_direct_input = trimmed;
      return await this.transitionTo(session, 'CONN_DONE', { isDirect: true });
    }

    // 6. Сбор контактов при подключении (CONN_03)
    if (session.currentStep === 'CONN_03') {
      session.variables.lead_contact = trimmed;
      return await this.transitionTo(session, 'CONN_DONE', { isStructured: true });
    }

    // 7. Заявка на смену тарифа (TAR_CHANGE)
    if (session.currentStep === 'TAR_CHANGE') {
      session.variables.desired_speed = trimmed;
      return await this.transitionTo(session, 'TAR_CHANGE_SUBMIT');
    }

    // 8. B2B заявка (TAR_B2B)
    if (session.currentStep === 'TAR_B2B') {
      session.variables.b2b_info = trimmed;
      return await this.transitionTo(session, 'CONN_DONE', { isB2B: true });
    }

    // Если на шаге есть явный next
    if (currentStepConfig.next && this.scenario[currentStepConfig.next]) {
      return await this.transitionTo(session, currentStepConfig.next);
    }

    // Фоллбэк: если пользователь просто пишет в меню, предлагаем опции или соединение
    return {
      stepId: session.currentStep,
      text: 'Я вас услышал! Выберите, пожалуйста, действие из меню ниже или свяжитесь с оператором:',
      buttons: (currentStepConfig.buttons && currentStepConfig.buttons.length > 0)
        ? currentStepConfig.buttons
        : [
            { text: '💬 Позвать оператора', next: 'OP_01' },
            { text: '↩️ В главное меню', next: 'START_01' }
          ]
    };
  }

  // Переход на следующий шаг со срабатыванием интеграций/действий
  async transitionTo(session, stepId, context = {}) {
    const config = this.scenario[stepId];
    if (!config) {
      throw new Error(`Step ${stepId} not found in scenario`);
    }

    session.currentStep = stepId;

    // Выполнение системных действий (Action / Integrations)
    await this.executeStepAction(session, stepId, context);

    // Особый случай: фоновый шаг автотеста сети (NET_02)
    if (stepId === 'NET_02') {
      const diagResult = await this.billing.checkLineDiagnostics(session.variables.user_phone, context.forceBranch);
      session.variables.diagnostics = diagResult;

      if (diagResult.status === 'ALARM' || diagResult.has_incident) {
        session.variables.incident_end_time = diagResult.incident_end_time || '14:30';
        return await this.transitionTo(session, 'NET_ALARM');
      } else if (diagResult.status === 'CABLE_CUT' || diagResult.port_status === 'down') {
        const ticket = await this.crm.createCableCutTicket(
          session.variables.epay || session.variables.contract_id,
          session.variables.user_phone,
          session.variables.address
        );
        session.variables.ticket_id = ticket.ticket_id;
        return await this.transitionTo(session, 'NET_CABLE_CUT');
      } else {
        return await this.transitionTo(session, 'NET_REBOOT');
      }
    }

    return await this.renderStep(session, stepId);
  }

  // Выполнение действий шагов
  async executeStepAction(session, stepId, context = {}) {
    const vars = session.variables;

    switch (stepId) {
      case 'PAY_DETAILS': {
        const details = await this.billing.getInvoiceDetails(vars.epay || vars.contract_id);
        vars.tariff_name = details.tariff_name;
        vars.tariff_price = details.tariff_price;
        vars.addon_price = details.addon_price;
        vars.balance_amount = details.balance_amount;
        break;
      }

      case 'PAY_WEBAPP': {
        vars.sbp_payment_url = this.payment.generateSbpLink(vars.epay || vars.contract_id, vars.balance_amount);
        break;
      }

      case 'TAR_CITY_SELECTED': {
        const tariffs = await this.billing.getTariffs(vars.user_city);
        vars.tariffs_list = tariffs.map((t, i) => `${i + 1}. «${t.name}» — ${t.price}`).join('\n');
        break;
      }

      case 'TAR_CHANGE_SUBMIT': {
        const lead = await this.crm.createLead({
          type: 'TARIFF_CHANGE',
          epay: vars.epay,
          desired_speed: vars.desired_speed,
          user_city: vars.user_city
        });
        vars.ticket_id = lead.lead_id;
        break;
      }

      case 'NET_01': {
        // подготовка к приему телефона
        break;
      }

      case 'NET_PORT_RESET': {
        await this.billing.restartSwitchPort(vars.epay || vars.contract_id);
        break;
      }

      case 'REQ_CHECK': {
        const ticket = await this.crm.findActiveTicket(vars.search_contact || vars.epay);
        vars.ticket_id = ticket.ticket_id;
        vars.ticket_type = ticket.ticket_type || 'Обслуживание линии';
        vars.ticket_status = ticket.ticket_status;
        vars.master_time = ticket.master_time;
        vars.master_name = ticket.master_name;
        vars.master_phone = ticket.master_phone;
        vars.ticket_issue = ticket.ticket_issue;
        break;
      }

      case 'REQ_REPAIR_CREATE': {
        const repairTicket = await this.crm.createCableCutTicket(
          vars.epay,
          vars.user_phone,
          vars.lead_address || 'Адрес по ЕПАЙ'
        );
        vars.ticket_id = repairTicket.ticket_id;
        vars.ticket_status = 'В очереди диспетчера';
        vars.master_time = 'Согласуется диспетчером';
        break;
      }

      case 'REQ_RESCHEDULE_DONE': {
        const slot = context.manualSlot || context.buttonValue || vars.selected_slot || 'tomorrow_10_14';
        const res = await this.crm.rescheduleTicket(vars.ticket_id, slot);
        vars.master_time = res.master_time;
        break;
      }

      case 'REQ_CANCEL_DONE': {
        await this.crm.cancelTicket(vars.ticket_id);
        break;
      }

      case 'CONN_DONE': {
        const leadData = {
          type: context.isB2B ? 'B2B' : context.isDirect ? 'DIRECT' : 'STRUCTURED',
          address: vars.lead_address || vars.lead_direct_input || '',
          service: vars.lead_service || 'Не указана',
          contact: vars.lead_contact || vars.lead_direct_input || vars.b2b_info || '',
          city: vars.user_city
        };
        const leadRes = await this.crm.createLead(leadData);
        vars.lead_id = leadRes.lead_id;
        break;
      }

      case 'OP_SALES': {
        session.inOperatorMode = true;
        session.operatorQueue = 'sales';
        await this.crm.routeToOperator({
          queue: 'sales',
          userId: session.userId,
          history: session.history
        });
        break;
      }

      case 'OP_01': {
        session.inOperatorMode = true;
        session.operatorQueue = 'support';
        await this.crm.routeToOperator({
          queue: 'support',
          userId: session.userId,
          contractId: vars.epay || vars.contract_id,
          history: session.history,
          diagnostics: vars.diagnostics || null
        });
        break;
      }

      default:
        break;
    }
  }

  // Отрендерить сообщение шага с подстановкой переменных
  async renderStep(session, stepId) {
    const config = this.scenario[stepId];
    if (!config) {
      return { stepId, text: 'Экран не найден.', buttons: [] };
    }

    let renderedText = config.text || '';
    // Подстановка {variable}
    for (const [key, value] of Object.entries(session.variables)) {
      const placeholder = `{${key}}`;
      if (renderedText.includes(placeholder)) {
        renderedText = renderedText.replaceAll(placeholder, value || '');
      }
    }

    // Подготовка кнопок
    const renderedButtons = (config.buttons || []).map(b => {
      let url = b.url;
      if (url && url.includes('{sbp_payment_url}')) {
        url = url.replace('{sbp_payment_url}', session.variables.sbp_payment_url);
      }
      return {
        text: b.text,
        next: b.next,
        url,
        value: b.value
      };
    });

    session.history.push({ from: 'bot', stepId, text: renderedText, timestamp: new Date().toISOString() });

    return {
      stepId,
      screenName: config.screenName,
      category: config.category,
      text: renderedText,
      buttons: renderedButtons,
      isAutoTransition: config.isAutoTransition,
      next: config.next
    };
  }
}
