import 'package:flutter_test/flutter_test.dart';
import '../lib/services/cabinet_parser.dart';

void main() {
  group('CabinetParser', () {
    test('parseCabinetHtml correctly extracts info', () {
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

    test('parseCabinetHtml throws on expired auth', () {
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
  });
}
