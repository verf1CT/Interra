// Сервис работы с CRM / Helpdesk / Службой выездных мастеров «Интерра»

export class CrmService {
  constructor(options = {}) {
    this.apiUrl = options.apiUrl || process.env.CRM_API_URL || '';
    this.apiToken = options.apiToken || process.env.CRM_API_TOKEN || '';
    this.salesChatId = options.salesChatId || process.env.TELEGRAM_SALES_CHAT_ID || '';
    this.isMock = !this.apiUrl;
  }

  // Создание заявки на монтаж (новый лид)
  async createLead(leadData) {
    if (!this.isMock) {
      const res = await fetch(`${this.apiUrl}/crm/lead`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiToken}`
        },
        body: JSON.stringify(leadData)
      });
      if (!res.ok) throw new Error(`CRM createLead failed: ${res.status}`);
      return await res.json();
    }

    const leadId = Math.floor(100000 + Math.random() * 900000);
    return {
      success: true,
      lead_id: String(leadId),
      created_at: new Date().toISOString(),
      status: 'NEW',
      ...leadData
    };
  }

  // Поиск активной заявки по номеру телефона или ЕПАЙ
  async findActiveTicket(searchContact) {
    if (!this.isMock) {
      const res = await fetch(`${this.apiUrl}/crm/tickets/active?query=${encodeURIComponent(searchContact)}`, {
        headers: { Authorization: `Bearer ${this.apiToken}` }
      });
      if (!res.ok) throw new Error(`CRM findActiveTicket failed: ${res.status}`);
      return await res.json();
    }

    return {
      ticket_id: '49281',
      ticket_type: 'Ремонт линии',
      ticket_status: 'В очереди диспетчера',
      master_time: 'Согласуется диспетчером',
      master_name: 'Дежурная бригада',
      master_phone: '+7 (3439) 66-00-00',
      ticket_issue: 'Диагностика кабельной линии / проверка домового свитча'
    };
  }

  // Получение детальной карточки заявки
  async getTicketDetails(ticketId) {
    if (!this.isMock) {
      const res = await fetch(`${this.apiUrl}/crm/tickets/${encodeURIComponent(ticketId)}`, {
        headers: { Authorization: `Bearer ${this.apiToken}` }
      });
      if (!res.ok) throw new Error(`CRM getTicketDetails failed: ${res.status}`);
      return await res.json();
    }

    return {
      ticket_id: ticketId || '49281',
      ticket_type: 'Ремонт линии',
      ticket_status: 'В работе',
      master_time: 'Согласуется диспетчером',
      master_name: 'Дежурная бригада',
      master_phone: '+7 (3439) 66-00-00',
      ticket_issue: 'Восстановление линии связи'
    };
  }

  // Перенос времени визита / фиксация пожелания по времени
  async rescheduleTicket(ticketId, newSlot) {
    if (!this.isMock) {
      const res = await fetch(`${this.apiUrl}/crm/tickets/${encodeURIComponent(ticketId)}/reschedule`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiToken}`
        },
        body: JSON.stringify({ slot: newSlot })
      });
      if (!res.ok) throw new Error(`CRM rescheduleTicket failed: ${res.status}`);
      return await res.json();
    }

    let timeText = newSlot;
    if (newSlot === 'tomorrow_10_14') timeText = 'Завтра (10:00 - 14:00)';
    if (newSlot === 'tomorrow_14_18') timeText = 'Завтра (14:00 - 18:00)';

    return {
      success: true,
      ticket_id: ticketId,
      master_time: timeText,
      updated_at: new Date().toISOString()
    };
  }

  // Отмена заявки на выезд
  async cancelTicket(ticketId) {
    if (!this.isMock) {
      const res = await fetch(`${this.apiUrl}/crm/tickets/${encodeURIComponent(ticketId)}/cancel`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${this.apiToken}` }
      });
      if (!res.ok) throw new Error(`CRM cancelTicket failed: ${res.status}`);
      return await res.json();
    }

    return {
      success: true,
      ticket_id: ticketId,
      status: 'CANCELLED'
    };
  }

  // Создание сервисной заявки по обрыву кабеля для ремонтной службы
  async createCableCutTicket(epay, phone, address) {
    const ticketId = Math.floor(40000 + Math.random() * 50000);
    return {
      ticket_id: String(ticketId),
      ticket_type: 'Ремонт линии связи',
      ticket_status: 'В очереди диспетчера',
      master_time: 'Согласуется диспетчером',
      master_name: 'Линейная бригада ремонтов',
      master_phone: '+7 (3439) 66-00-00',
      ticket_issue: 'Физический обрыв витой пары (Port Down / TDR-обрыв)'
    };
  }

  // Маршрутизация диалога в Helpdesk операторам (техподдержка / продажи)
  async routeToOperator({ queue, userId, contractId, history = [], diagnostics = {} }) {
    if (!this.isMock) {
      const res = await fetch(`${this.apiUrl}/helpdesk/handoff`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiToken}`
        },
        body: JSON.stringify({
          queue,
          user_id: userId,
          contract_id: contractId,
          history,
          diagnostics,
          timestamp: new Date().toISOString()
        })
      });
      return await res.json();
    }

    return {
      success: true,
      queued: true,
      queue_name: queue === 'sales' ? 'Отдел продаж' : 'Техническая поддержка',
      dialog_id: `DLG-${Date.now().toString().slice(-6)}`
    };
  }
}
