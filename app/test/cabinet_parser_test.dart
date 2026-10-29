import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/services/cabinet_parser.dart';

void main() {
  group('CabinetParser', () {
    test('decodeResponseBody avoids Latin-1 mojibake and recovers UTF-8', () {
      const originalText = '<html><body><div>ФИО: Иванов Иван</div><div>Баланс: 450 руб</div></body></html>';
      final utf8Bytes = utf8.encode(originalText);
      final decoded = CabinetParser.decodeResponseBody(utf8Bytes);
      expect(decoded, originalText);
      expect(decoded.contains('Иванов'), true);
      expect(decoded.contains('Баланс'), true);
    });

    test('parseCabinetHtml correctly extracts info (mock format)', () {
      const html = '''
        <html>
        <body>
          <div>Баланс: -1 500,50 руб</div>
          <div>Лицевой счёт: 123456789</div>
          <div>Полное ФИО: Иванов Иван Иванович</div>
          <div>Тарифный план: Супер Интернет 100</div>
        </body>
        </html>
      ''';
      
      final data = CabinetParser.parseCabinetHtml(html);
      
      expect(data.balance, -1500.50);
      expect(data.account, '123456789');
      expect(data.fullName, 'Иванов Иван Иванович');
      expect(data.tariff, 'Супер Интернет 100');
    });

    test('parseCabinetHtml correctly extracts info from real UTM5 table structure', () {
      const html = '''
        <html>
        <body>
          <table class="b-account">
            <tr>
              <td align="right"><b>Основной баланс:</b></td>
              <td>550,20 руб.</td>
            </tr>
            <tr>
              <td align="right"><b>Лицевой счет:</b></td>
              <td>98765432</td>
            </tr>
            <tr>
              <td align="right"><b>ФИО:</b></td>
              <td>Косолапов Иван Александрович</td>
            </tr>
            <tr>
              <td align="right"><b>Тариф:</b></td>
              <td>Комфорт 200</td>
            </tr>
          </table>
        </body>
        </html>
      ''';
      
      final data = CabinetParser.parseCabinetHtml(html);
      
      expect(data.balance, 550.20);
      expect(data.account, '98765432');
      expect(data.fullName, 'Косолапов Иван Александрович');
      expect(data.tariff, 'Комфорт 200');
    });

    test('parseCabinetHtml correctly parses 4-column multi-cell table rows', () {
      const html = '''
        <html>
        <body>
          <table>
            <tr>
              <th>Лицевой счет:</th>
              <td>112233</td>
              <th>Основной баланс:</th>
              <td>−350,00 руб.</td>
            </tr>
            <tr>
              <th>Абонент:</th>
              <td>Сидоров Алексей</td>
              <th>Тариф:</th>
              <td>Премиум 500</td>
            </tr>
          </table>
        </body>
        </html>
      ''';
      
      final data = CabinetParser.parseCabinetHtml(html);
      
      expect(data.account, '112233');
      expect(data.balance, -350.0);
      expect(data.fullName, 'Сидоров Алексей');
      expect(data.tariff, 'Премиум 500');
    });

    test('parseCabinetHtml correctly handles alternative labels and "е" instead of "ё"', () {
      const html = '''
        <html>
        <body>
          <p>Договор № 445566</p>
          <p>Абонент: Петров Петр</p>
          <p>Баланс: 0.00 руб</p>
          <p>Тариф: Базовый</p>
        </body>
        </html>
      ''';
      
      final data = CabinetParser.parseCabinetHtml(html);
      
      expect(data.account, '445566');
      expect(data.fullName, 'Петров Петр');
      expect(data.balance, 0.0);
      expect(data.tariff, 'Базовый');
    });

    test('parseCabinetHtml throws on expired auth with password input', () {
      const html = '''
        <html>
        <body>
          <input name="pass" type="password">
        </body>
        </html>
      ''';
      
      expect(() => CabinetParser.parseCabinetHtml(html), throwsException);
    });

    test('parsePaymentsHtml extracts payments table', () {
      const html = '''
        <html>
        <body>
          <table>
            <tr>
              <td>Дата</td>
              <td>Сумма</td>
              <td>Комментарий</td>
            </tr>
            <tr>
              <td>01.01.2024</td>
              <td> 500,00 </td>
              <td>Оплата по карте</td>
            </tr>
            <tr>
              <td>02.01.2024</td>
              <td>-100,50</td>
              <td>Абонентская плата</td>
            </tr>
          </table>
        </body>
        </html>
      ''';
      
      final payments = CabinetParser.parsePaymentsHtml(html);
      
      expect(payments.length, 2);
      expect(payments[0].date, '01.01.2024');
      expect(payments[0].amount, 500.0);
      expect(payments[0].comment, 'Оплата по карте');
      
      expect(payments[1].date, '02.01.2024');
      expect(payments[1].amount, -100.5);
      expect(payments[1].comment, 'Абонентская плата');
    });

    test('parseServicesHtml extracts services table', () {
      const html = '''
        <html>
        <body>
          <table>
            <tr>
              <td>Услуга</td>
              <td>Стоимость</td>
              <td>Статус</td>
            </tr>
            <tr>
              <td>Интернет 100 Мбит</td>
              <td>500 руб.</td>
              <td>Активна</td>
            </tr>
            <tr>
              <td>Итого</td>
              <td>500 руб.</td>
              <td></td>
            </tr>
          </table>
        </body>
        </html>
      ''';
      
      final services = CabinetParser.parseServicesHtml(html);
      
      expect(services.length, 1);
      expect(services[0].name, 'Интернет 100 Мбит');
      expect(services[0].cost, '500 руб.');
      expect(services[0].status, 'Активна');
    });

    test('parseCabinetHtml strictly ignores .b-informer phone/address and .b-tab navigation', () {
      const html = '''
        <html>
        <body>
          <div class="sidebar">
            <div class="nav-footer">
              <a href="tel:88007700010">8 800 77-000-10</a>
            </div>
          </div>
          <table class="b-informer">
            <tr>
              <td>Для абонентов:</td>
              <td>Единый круглосуточный телефон: 8-800-77-000-10 (звонок бесплатный) .Центр обслуживания: ул. Трубников, 24Помощь: https://pervouralsk.interra.ru/help/</td>
            </tr>
          </table>
          <table class="b-tab">
            <tr>
              <td>Тарифы</td>
              <td>Premium TV</td>
              <td>Пополнение</td>
            </tr>
          </table>
          <table class="b-account">
            <tr>
              <td align="right"><b>Основной баланс:</b></td>
              <td>10 000 руб.</td>
            </tr>
            <tr>
              <td align="right"><b>Лицевой счет:</b></td>
              <td>458921</td>
            </tr>
            <tr>
              <td align="right"><b>Абонент:</b></td>
              <td>Косолапов Иван Александрович</td>
            </tr>
          </table>
          <table class="tlt">
            <tr>
              <td>Интернет 100 Мбит/с</td>
              <td>650.00 руб.</td>
              <td>Активна</td>
            </tr>
          </table>
        </body>
        </html>
      ''';

      final data = CabinetParser.parseCabinetHtml(html);

      expect(data.balance, 10000.0);
      expect(data.account, '458921');
      expect(data.account != '800', true);
      expect(data.fullName, 'Косолапов Иван Александрович');
      expect(data.fullName.contains('8-800'), false);
      expect(data.tariff, 'Интернет 100 Мбит/с');
      expect(data.tariff.contains('PremiumTV'), false);
    });

    test('parseCabinetHtml falls back to contract number when subscriber name is absent', () {
      const html = '''
        <html>
        <body>
          <table class="b-account">
            <tr>
              <td align="right"><b>Основной баланс:</b></td>
              <td>1 250 руб.</td>
            </tr>
            <tr>
              <td align="right"><b>Лицевой счет:</b></td>
              <td>778899</td>
            </tr>
          </table>
          <table class="tlt">
            <tr>
              <td>Комфорт 200</td>
              <td>800.00 руб.</td>
            </tr>
          </table>
        </body>
        </html>
      ''';

      final data = CabinetParser.parseCabinetHtml(html);

      expect(data.balance, 1250.0);
      expect(data.account, '778899');
      expect(data.fullName, 'Договор № 778899');
      expect(data.tariff, 'Комфорт 200');
    });

    test('parseCabinetHtml correctly parses address, login, and "Нет тарифа" with passport required', () {
      const html = '''
        <html>
        <body>
          <p>Клиент: Мешкой Михаил Максимович (ХВОЙНАЯ (МОЛОДЕЖНЫЙ) 5- / 216997test)</p>
          <p>Действующий тариф: Нет тарифа</p>
          <p>Не хватает учётных данных.</p>
          <p>Для выбора тарифа необходимо ввести паспортные данные.</p>
          <p>Ваш лицевой счет для оплаты в платежных системах – 276997</p>
          <p>Основной баланс: 10 000 руб.</p>
        </body>
        </html>
      ''';

      final data = CabinetParser.parseCabinetHtml(html);

      expect(data.fullName, 'Мешкой Михаил Максимович');
      expect(data.address, 'ХВОЙНАЯ (МОЛОДЕЖНЫЙ) 5-');
      expect(data.login, '216997test');
      expect(data.account, '276997');
      expect(data.tariff, 'Нет тарифа');
      expect(data.needsPassportData, true);
      expect(data.balance, 10000.0);
    });

    test('parsePaymentsHtml correctly parses NetUP UTM5 .b-operation table', () {
      const html = '''
        <html>
        <body>
          <table class="b-operation">
            <tr class="thead">
              <td>выполнено</td>
              <td>оператор</td>
              <td>операция</td>
              <td>пользователь</td>
              <td>сумма</td>
              <td>комментарий</td>
            </tr>
            <tr>
              <td>16-10-2026 23:59</td>
              <td>SYSTEM</td>
              <td>отключен</td>
              <td>Мешкой Михаил Максимович</td>
              <td>0.00</td>
              <td>32</td>
            </tr>
            <tr>
              <td>17-10-2026 08:35</td>
              <td>SYSTEM</td>
              <td>включен</td>
              <td>Мешкой Михаил Максимович</td>
              <td>0.00</td>
              <td>32</td>
            </tr>
          </table>
          <p>За октябрь 2026 года платежей на сумму : 0 руб.</p>
        </body>
        </html>
      ''';

      final items = CabinetParser.parsePaymentsHtml(html);

      expect(items.length, 2);
      expect(items[0].date, '16-10-2026 23:59');
      expect(items[0].operator, 'SYSTEM');
      expect(items[0].operation, 'отключен');
      expect(items[0].amount, 0.0);
      expect(items[0].comment, '32');

      expect(items[1].date, '17-10-2026 08:35');
      expect(items[1].operator, 'SYSTEM');
      expect(items[1].operation, 'включен');
      expect(items[1].amount, 0.0);
      expect(items[1].comment, '32');
    });

    test('buildPassportFormData dynamically extracts form fields, formats passport & dates', () {
      const html = '''
        <html>
        <body>
          <form action="aaainfo" method="POST">
            <input type="hidden" name="login" value="test_token_123">
            <input type="hidden" name="oper" value="tariffs">
            <input type="hidden" name="action" value="save_doc">
            <table>
              <tr>
                <td>десять цифр, серия и номер паспорта СССС-НННННН:</td>
                <td><input type="text" name="doc_num" value=""></td>
              </tr>
              <tr>
                <td>дата когда выдан паспорт ДД.ММ.ГГГГ:</td>
                <td><input type="text" name="doc_date" value=""></td>
              </tr>
              <tr>
                <td>кем выдан паспорт:</td>
                <td><input type="text" name="doc_org" value=""></td>
              </tr>
              <tr>
                <td>дата рождения абонента ДД.ММ.ГГГГ:</td>
                <td><input type="text" name="birth_date" value=""></td>
              </tr>
              <tr>
                <td>с Соглашением о предоставлении услуг ознакомлен</td>
                <td><input type="checkbox" name="agree" value="1"></td>
              </tr>
            </table>
            <input type="submit" name="save_btn" value="записать данные">
          </form>
        </body>
        </html>
      ''';

      final formData = CabinetParser.buildPassportFormData(
        html,
        passport: '6504 123456',
        issueDate: '15/08/2014',
        issuedBy: 'Отделом УФМС Первоуральск',
        birthDate: '01-05-1992',
      );

      // Hidden fields
      expect(formData['login'], 'test_token_123');
      expect(formData['oper'], 'tariffs');
      expect(formData['action'], 'save_doc');

      // Mapped inputs with normalized formats
      expect(formData['doc_num'], '6504-123456');
      expect(formData['doc_date'], '15.08.2014');
      expect(formData['doc_org'], 'Отделом УФМС Первоуральск');
      expect(formData['birth_date'], '01.05.1992');

      // Checkbox and submit
      expect(formData['agree'], '1');
      expect(formData['save_btn'], 'записать данные');

      // Fallback keys also present
      expect(formData['passport'], '6504-123456');
      expect(formData['passport_date'], '15.08.2014');
      expect(formData['passport_who'], 'Отделом УФМС Первоуральск');
      expect(formData['agreement'], '1');
    });

    test('isPassportSavedSuccessfully correctly detects validation failure or success', () {
      const failedHtml = '''
        <html>
        <body>
          <p>Не хватает учётных данных.</p>
          <p>Для выбора тарифа необходимо ввести паспортные данные.</p>
          <form><input type="text" name="doc_num"></form>
        </body>
        </html>
      ''';

      const successHtml = '''
        <html>
        <body>
          <h3>Доступные тарифные планы</h3>
          <table class="tariffs">
            <tr><td>Комфорт 100</td><td>550 руб.</td></tr>
            <tr><td>Комфорт 200</td><td>750 руб.</td></tr>
          </table>
        </body>
        </html>
      ''';

      expect(CabinetParser.isPassportSavedSuccessfully(failedHtml), false);
      expect(CabinetParser.isPassportSavedSuccessfully(''), false);
      expect(CabinetParser.isPassportSavedSuccessfully(successHtml), true);
    });
  });
}
