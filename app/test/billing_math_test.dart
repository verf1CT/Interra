import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/services/cabinet_parser.dart';
import 'package:lk_interra/utils/billing_math.dart';

ServiceItem svc(String cost) => ServiceItem(name: 'x', status: 'Активен', cost: cost);

PaymentItem pay(String date, double amount) => PaymentItem(date: date, amount: amount);

void main() {
  group('monthlyFee', () {
    test('суммирует только месячные цены', () {
      expect(
        monthlyFee([svc('750 ₽ / мес'), svc('Включено'), svc('150 руб./мес.')]),
        900,
      );
    });

    test('разовые платежи и пустые цены не считаются', () {
      expect(monthlyFee([svc('500 ₽'), svc(''), svc('Включено')]), isNull);
    });

    test('пробелы в тысячах и копейки', () {
      expect(monthlyFee([svc('1 250,50 ₽ / мес')]), 1250.5);
    });
  });

  test('monthsCovered', () {
    expect(monthsCovered(1250, 750), 1);
    expect(monthsCovered(3000, 750), 4);
    expect(monthsCovered(-10, 750), 0);
    expect(monthsCovered(500, null), isNull);
  });

  test('parseBillingDate', () {
    expect(parseBillingDate('04.11.2026 14:22'), DateTime(2026, 11, 4, 14, 22));
    expect(parseBillingDate('01.10.2026'), DateTime(2026, 10, 1));
    expect(parseBillingDate('вчера'), isNull);
    expect(parseBillingDate('40.13.2026'), isNull);
  });

  test('форматы дат и сумм', () {
    final now = DateTime(2026, 11, 24);
    expect(monthTitle(DateTime(2026, 11, 4)), 'Ноябрь 2026');
    expect(shortDate(DateTime(2026, 11, 4), now: now), '4 ноября');
    expect(shortDate(DateTime(2025, 3, 1), now: now), '1 марта 2025');
    expect(shortTime(DateTime(2026, 11, 1)), '');
    expect(shortTime(DateTime(2026, 11, 1, 9, 5)), '09:05');
    expect(signedMoney(750), '+750 ₽');
    expect(signedMoney(-750), '−750 ₽');
  });

  test('lastTopUp берёт самое свежее пополнение', () {
    final items = [
      pay('01.11.2026 00:00', -750),
      pay('25.10.2026 19:10', 750),
      pay('04.11.2026 14:22', 300),
    ];
    expect(lastTopUp(items)!.amount, 300);
    expect(lastTopUp([pay('01.11.2026', -750)]), isNull);
  });

  test('totalsForMonth', () {
    final t = totalsForMonth([
      pay('04.11.2026 14:22', 750),
      pay('01.11.2026 00:00', -750),
      pay('25.10.2026 19:10', 1000),
    ], 2026, 11);
    expect(t.income, 750);
    expect(t.expense, -750);
  });

  test('firstName и приветствие', () {
    expect(firstName('Иванов Иван Иванович'), 'Иван');
    expect(firstName('Абонент'), isNull);
    expect(firstName('Иванов И.И. (Дача)'), isNull);
    expect(greeting(DateTime(2026, 1, 1, 8)), 'Доброе утро');
    expect(greeting(DateTime(2026, 1, 1, 20)), 'Добрый вечер');
  });
}
