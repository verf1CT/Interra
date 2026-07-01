import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/services/balance_store.dart';

void main() {
  group('BalanceStore.parseAmount', () {
    test('простое значение из кабинета', () {
      expect(BalanceStore.parseAmount('1846.03'), 1846.03);
    });
    test('запятая как разделитель', () {
      expect(BalanceStore.parseAmount('1846,03'), 1846.03);
    });
    test('пробелы-разряды и неразрывные пробелы', () {
      expect(BalanceStore.parseAmount('1 846.03'), 1846.03);
      expect(BalanceStore.parseAmount('12 345,5'), 12345.5);
    });
    test('отрицательный баланс', () {
      expect(BalanceStore.parseAmount('-12.5'), -12.5);
    });
    test('мусор → null', () {
      expect(BalanceStore.parseAmount(''), isNull);
      expect(BalanceStore.parseAmount('нет данных'), isNull);
    });
  });

  group('BalanceStore.format', () {
    test('целое с разрядами', () {
      expect(BalanceStore.format(1846), '1 846 ₽');
    });
    test('копейки', () {
      expect(BalanceStore.format(1846.03), '1 846,03 ₽');
    });
    test('отрицательное', () {
      expect(BalanceStore.format(-12.5), '−12,50 ₽');
    });
    test('миллион', () {
      expect(BalanceStore.format(1234567.8), '1 234 567,80 ₽');
    });
    test('ноль', () {
      expect(BalanceStore.format(0), '0 ₽');
    });
  });
}
