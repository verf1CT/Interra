import { describe, it, expect, beforeEach } from 'vitest';
import express from 'express';
import { BotEngine } from '../src/bot/botEngine.js';
import { TelegramClient } from '../src/bot/telegramClient.js';
import { TelegramHandler } from '../src/bot/telegramHandler.js';
import { MaxClient } from '../src/bot/maxClient.js';
import { MaxHandler } from '../src/bot/maxHandler.js';
import { botRouter } from '../src/routes/bot.js';

describe('Интерра Чат-бот на платформе MAX (сценарий самообслуживания)', () => {
  let engine;
  const userId = 'test-subscriber-42';

  beforeEach(() => {
    engine = new BotEngine();
  });

  it('1. Сегментация: Старт бота и выбор ветки действующего абонента', async () => {
    const start = await engine.handleStart(userId);
    expect(start.stepId).toBe('START_01');
    expect(start.text).toContain('Здравствуйте! Я виртуальный помощник компании «Интерра»');
    expect(start.buttons).toHaveLength(2);

    const subscriberMenu = await engine.handleButtonClick(userId, 'CURRENT_01');
    expect(subscriberMenu.stepId).toBe('CURRENT_01');
    expect(subscriberMenu.text).toContain('Рады вас видеть! Чем могу помочь?');
    expect(subscriberMenu.buttons.length).toBeGreaterThanOrEqual(6);
  });

  it('2. Личный кабинет: Баланс, детализация начислений по ЕПАЙ и генерация СБП ссылки', async () => {
    await engine.handleStart(userId);
    await engine.handleButtonClick(userId, 'CURRENT_01');

    const lk = await engine.handleButtonClick(userId, 'LK_01');
    expect(lk.stepId).toBe('LK_01');

    const details = await engine.handleButtonClick(userId, 'PAY_DETAILS');
    expect(details.stepId).toBe('PAY_DETAILS');
    expect(details.text).toContain('Расшифровка начислений за текущий период по лицевому счёту (ЕПАЙ) 504600');
    expect(details.text).toContain('Тарифный план «Комфорт 200 + ТВ»');

    const sbp = await engine.handleButtonClick(userId, 'PAY_WEBAPP');
    expect(sbp.stepId).toBe('PAY_WEBAPP');
    expect(sbp.text).toContain('Оплатить услуги без комиссии можно в 1 клик через СБП');
    expect(sbp.buttons[0].url).toContain('https://interra.ru/pay?contract=504600');
  });

  it('3. Льготный период 10 дней: Разъяснение работы скорости 512 Кбит/с', async () => {
    await engine.handleStart(userId);
    await engine.handleButtonClick(userId, 'CURRENT_01');
    await engine.handleButtonClick(userId, 'LK_01');

    const graceInfo = await engine.handleButtonClick(userId, 'PAY_GRACE_INFO');
    expect(graceInfo.stepId).toBe('PAY_GRACE_INFO');
    expect(graceInfo.text).toContain('512 Кбит/с');
    expect(graceInfo.text).toContain('по номеру ЕПАЙ: 504600');
    expect(graceInfo.buttons[0].next).toBe('PAY_WEBAPP');
  });

  it('4. Тарифы по городам: Выбор города и динамическая загрузка сетки', async () => {
    await engine.handleStart(userId);
    await engine.handleButtonClick(userId, 'CURRENT_01');

    const tar01 = await engine.handleButtonClick(userId, 'TAR_01');
    expect(tar01.stepId).toBe('TAR_01');

    const tarCity = await engine.handleButtonClick(userId, 'TAR_CITY');
    expect(tarCity.stepId).toBe('TAR_CITY');

    const revdaTariffs = await engine.handleButtonClick(userId, 'TAR_CITY_SELECTED', 'Ревда');
    expect(revdaTariffs.stepId).toBe('TAR_CITY_SELECTED');
    expect(revdaTariffs.text).toContain('Актуальные тарифы для г. Ревда');
    expect(revdaTariffs.text).toContain('Ревда Драйв');
  });

  it('5. Диагностика сети: Ветка массовой аварии (ALARM)', async () => {
    await engine.handleStart(userId);
    await engine.handleButtonClick(userId, 'CURRENT_01');
    await engine.handleButtonClick(userId, 'NET_01');

    // Номер с окончанием 111 симулирует аварию
    const netAlarm = await engine.handleTextInput(userId, '+79991234111');
    expect(netAlarm.stepId).toBe('NET_ALARM');
    expect(netAlarm.text).toContain('зафиксированы восстановительные/плановые работы на оборудовании');
  });

  it('6. Диагностика сети: Ветка физического обрыва кабеля (CABLE_CUT) и вызов ремонтников', async () => {
    await engine.handleStart(userId);
    await engine.handleButtonClick(userId, 'CURRENT_01');
    await engine.handleButtonClick(userId, 'NET_01');

    // Номер с окончанием 222 симулирует обрыв кабеля
    const cableCut = await engine.handleTextInput(userId, '+79991234222');
    expect(cableCut.stepId).toBe('NET_CABLE_CUT');
    expect(cableCut.text).toContain('Диагностика выявила физическое отсутствие сигнала на кабеле');
    expect(cableCut.buttons[0].next).toBe('REQ_REPAIR_CREATE');

    const repairCreate = await engine.handleButtonClick(userId, 'REQ_REPAIR_CREATE');
    expect(repairCreate.stepId).toBe('REQ_REPAIR_CREATE');
    expect(repairCreate.text).toContain('Ремонтная служба формирует маршрутные листы');
  });

  it('7. Диагностика сети: Успешный цикл перезагрузки роутера и сброса порта', async () => {
    await engine.handleStart(userId);
    await engine.handleButtonClick(userId, 'CURRENT_01');
    await engine.handleButtonClick(userId, 'NET_01');

    // Обычный номер -> Порт Up, первичная перезагрузка роутера
    const rebootStep = await engine.handleTextInput(userId, '+79991234567');
    expect(rebootStep.stepId).toBe('NET_REBOOT');
    expect(rebootStep.text).toContain('Отключите роутер от розетки на 30 секунд');

    // Абонент сообщает, что не помогло
    const portReset = await engine.handleButtonClick(userId, 'NET_PORT_RESET');
    expect(portReset.stepId).toBe('NET_PORT_RESET');
    expect(portReset.isAutoTransition).toBe(true);

    // Автоматический переход к проверке
    const resetCheck = await engine.transitionTo(engine.getSession(userId), portReset.next);
    expect(resetCheck.stepId).toBe('NET_RESET_CHECK');
    expect(resetCheck.text).toContain('Сетевой порт перезапущен, сессия обновлена');

    // Проблема решена
    const success = await engine.handleButtonClick(userId, 'NET_SUCCESS');
    expect(success.stepId).toBe('NET_SUCCESS');
    expect(success.text).toContain('Отлично, рады были помочь!');
  });

  it('8. Статус заявки мастера: Поиск по ЕПАЙ и перенос времени визита', async () => {
    await engine.handleStart(userId);
    await engine.handleButtonClick(userId, 'CURRENT_01');

    const req01 = await engine.handleButtonClick(userId, 'REQ_01');
    expect(req01.stepId).toBe('REQ_01');

    const reqCheck = await engine.handleTextInput(userId, '504600');
    expect(reqCheck.stepId).toBe('REQ_CHECK');
    expect(reqCheck.text).toContain('Информация по вашей заявке №49281');

    const reschedule = await engine.handleButtonClick(userId, 'REQ_RESCHEDULE');
    expect(reschedule.stepId).toBe('REQ_RESCHEDULE');

    const done = await engine.handleButtonClick(userId, 'REQ_RESCHEDULE_DONE', 'tomorrow_14_18');
    expect(done.stepId).toBe('REQ_RESCHEDULE_DONE');
    expect(done.text).toContain('Завтра (14:00 - 18:00)');
  });

  it('9. Воронка продаж: Заявка от нового клиента на монтаж (Стандартная & Экспресс)', async () => {
    // Стандартная воронка в 3 шага
    await engine.handleStart(userId);
    const newClient = await engine.handleButtonClick(userId, 'NEW_01');
    expect(newClient.stepId).toBe('NEW_01');

    const conn01 = await engine.handleButtonClick(userId, 'CONN_01');
    expect(conn01.stepId).toBe('CONN_01');

    const conn02 = await engine.handleTextInput(userId, 'Первоуральск, пр. Ильича 30');
    expect(conn02.stepId).toBe('CONN_02');

    const conn03 = await engine.handleButtonClick(userId, 'CONN_03', 'flat_net_tv');
    expect(conn03.stepId).toBe('CONN_03');

    const connDone = await engine.handleTextInput(userId, 'Александр, +79120000000');
    expect(connDone.stepId).toBe('CONN_DONE');
    expect(connDone.text).toContain('Заявка на монтаж зарегистрирована под номером #');

    // Экспресс-воронка в 1 шаг (CONN_DIRECT)
    const directUser = 'user-direct-1';
    await engine.handleStart(directUser);
    await engine.handleButtonClick(directUser, 'NEW_01');
    await engine.handleButtonClick(directUser, 'CONN_DIRECT');
    const directDone = await engine.handleTextInput(directUser, 'Ревда, Горького 12, кв 5. Телефон 89221112233');
    expect(directDone.stepId).toBe('CONN_DONE');
    expect(directDone.text).toContain('Менеджер отдела продаж свяжется с вами в течение 15 минут');
  });

  it('10. Эскалация на оператора: Перевод контекста и диалоговый режим', async () => {
    await engine.handleStart(userId);
    await engine.handleButtonClick(userId, 'CURRENT_01');

    const opStep = await engine.handleButtonClick(userId, 'OP_01');
    expect(opStep.stepId).toBe('OP_01');
    expect(opStep.text).toContain('Соединяю вас со специалистом службы поддержки');

    const session = engine.getSession(userId);
    expect(session.inOperatorMode).toBe(true);

    const dialogReply = await engine.handleTextInput(userId, 'У меня упала скорость до 10 Мбит');
    expect(dialogReply.stepId).toBe('IN_OPERATOR_DIALOG');
    expect(dialogReply.text).toContain('Ваше сообщение передано оператору');

    // Выход из диалога с оператором
    const backToMenu = await engine.handleTextInput(userId, 'меню');
    expect(backToMenu.stepId).toBe('CURRENT_01');
    expect(session.inOperatorMode).toBe(false);
  });

  it('11. TelegramClient и TelegramHandler работают в dry-run режиме без ошибок', async () => {
    const tgClient = new TelegramClient('change-me-token');
    expect(tgClient.isConfigured).toBe(false);

    const sent = await tgClient.sendMessage(123456, 'Тест');
    expect(sent.ok).toBe(true);

    const tgHandler = new TelegramHandler(engine, tgClient);

    await tgHandler.handleUpdate({
      message: { chat: { id: 123456 }, text: '/start' }
    });

    await tgHandler.handleUpdate({
      callback_query: {
        id: 'cb-123',
        message: { chat: { id: 123456 }, message_id: 10 },
        data: JSON.stringify({ n: 'CURRENT_01' })
      }
    });

    const session = engine.getSession('123456');
    expect(session.currentStep).toBe('CURRENT_01');
  });

  it('12. MaxClient и MaxHandler (платформа MAX business.max.ru) корректно обрабатывают события', async () => {
    const maxClient = new MaxClient('test-max-token');
    expect(maxClient.isConfigured).toBe(false);

    const keyboard = maxClient.formatKeyboard([
      { text: 'Личный кабинет', next: 'LK_01' },
      { text: 'Сайт', url: 'https://interra.ru' }
    ]);

    expect(keyboard.type).toBe('inline_keyboard');
    expect(keyboard.payload.buttons).toHaveLength(2);
    expect(keyboard.payload.buttons[0][0].type).toBe('callback');
    expect(keyboard.payload.buttons[1][0].type).toBe('link');

    const maxHandler = new MaxHandler(engine, maxClient);

    // 1. Событие bot_started
    await maxHandler.handleUpdate({
      update_type: 'bot_started',
      chat_id: 999,
      user: { user_id: 999, first_name: 'Иван' }
    });

    let session = engine.getSession('999');
    expect(session.currentStep).toBe('START_01');

    // 2. Событие message_callback (нажатие кнопки)
    await maxHandler.handleUpdate({
      update_type: 'message_callback',
      callback: {
        callback_id: 'max-cb-1',
        payload: JSON.stringify({ n: 'CURRENT_01' }),
        user: { user_id: 999, first_name: 'Иван' }
      }
    });

    expect(session.currentStep).toBe('CURRENT_01');

    // 3. Событие message_created (ввод текста)
    await maxHandler.handleUpdate({
      update_type: 'message_created',
      message: {
        sender: { user_id: 999 },
        body: { text: 'позови человека' }
      }
    });

    expect(session.history.length).toBeGreaterThan(0);
  });
});
