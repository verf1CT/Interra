import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/services/cabinet_parser.dart';

void main() {
  group('CabinetParser restriction and accounts parsing', () {
    test('parses restricted status and recommended payment from negative balance HTML', () {
      const html = '''
        <html>
        <body>
          <div class="b-account">
            <table>
              <tr><td>ФИО:</td><td>Михайлов Александр</td></tr>
              <tr><td>Лицевой счет:</td><td>192351</td></tr>
              <tr><td>Тариф:</td><td>Безлимитный 100</td></tr>
              <tr><td>Основной баланс:</td><td>-349.07 руб.</td></tr>
            </table>
          </div>
          <p>На счете -349.07 руб. Услуги связи ограничены.</p>
          <p>Пополнить баланс лицевого счета. Рекомендуемая сумма платежа: 359 руб.</p>
        </body>
        </html>
      ''';

      final data = CabinetParser.parseCabinetHtml(html);

      expect(data.balance, -349.07);
      expect(data.isRestricted, true);
      expect(data.recommendedPayment, '359 руб.');
      expect(data.needsPassportData, false);
      expect(data.tariff, 'Безлимитный 100');
    });

    test('parses multiple account options from selection list page', () {
      const html = '''
        <html>
        <body>
          <h3>Интерра Личный кабинет</h3>
          <div class="accounts">
            <a href="?login=30407call.123">CallCentr 487 (герцена 3-)</a>
            <a href="?login=30408router.123">CallCentr Router (герцена 3-)</a>
            <a href="?login=30409user.123">Мосолов Александр Юрьевич (Береговая 56-51)</a>
          </div>
        </body>
        </html>
      ''';

      final data = CabinetParser.parseCabinetHtml(html);

      expect(data.accounts.length, 3);
      expect(data.accounts[0].name, 'CallCentr 487');
      expect(data.accounts[0].address, 'герцена 3-');
      expect(data.accounts[0].loginUrl, '?login=30407call.123');

      expect(data.accounts[2].name, 'Мосолов Александр Юрьевич');
      expect(data.accounts[2].address, 'Береговая 56-51');
    });

    test('accountPageUrl берёт login из ссылки и грузит aaainfo нужной страницы', () {
      expect(
        CabinetParser.accountPageUrl('?login=30407call.123', oper: 'tariffs'),
        'https://stat.interra.ru/cgi-bin/utm5/aaainfo?login=30407call.123&oper=tariffs',
      );
      expect(
        CabinetParser.accountPageUrl('aaainfo?login=X.1&oper=info'),
        'https://stat.interra.ru/cgi-bin/utm5/aaainfo?login=X.1&oper=info',
      );
      expect(CabinetParser.accountPageUrl('/cgi-bin/utm5/other'), isNull);
    });

    test('isPlaceholderName узнаёт заглушки парсера', () {
      expect(CabinetParser.isPlaceholderName('Абонент'), true);
      expect(CabinetParser.isPlaceholderName('Договор № 192351'), true);
      expect(CabinetParser.isPlaceholderName('Мосолов Александр'), false);
    });

    test('safeTariff == "Нет тарифа" does not trigger needsPassportData without explicit notice', () {
      const html = '''
        <html>
        <body>
          <div class="b-account">
            <table>
              <tr><td>Абонент:</td><td>Елисеев Александр Викторович</td></tr>
              <tr><td>Лицевой счет:</td><td>550619</td></tr>
              <tr><td>Адрес:</td><td>БЕРЕГОВАЯ 56-51</td></tr>
              <tr><td>Баланс:</td><td>400.28 руб.</td></tr>
            </table>
          </div>
        </body>
        </html>
      ''';

      final data = CabinetParser.parseCabinetHtml(html);

      expect(data.account, '550619');
      expect(data.tariff, 'Нет тарифа');
      expect(data.needsPassportData, false);
      expect(data.isRestricted, false);
    });
  });

  test('linkKey отбрасывает последний кусок ссылки договора', () {
    expect(CabinetParser.linkKey('aaainfo?login=ab.123456.987654321000000001'),
        'ab.123456');
    expect(CabinetParser.linkKey('aaainfo?login=ab.123456.111&oper=info'),
        'ab.123456');
    expect(CabinetParser.linkKey('?login=plain'), 'plain');
  });
}
