import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/services/billing_api.dart';

void main() {
  group('BbbResponse.parse', () {
    test('строка в кавычках → data без кавычек', () {
      final r = BbbResponse.parse('"178123456789012345678901"');
      expect(r.isOk, true);
      expect(r.data, '178123456789012345678901');
      expect(r.code, isNull);
    });

    test('ссылка ?login=… → data', () {
      final r = BbbResponse.parse('"?login=X.123"');
      expect(r.isOk, true);
      expect(r.data, '?login=X.123');
    });

    test('код 0 → ошибка без data', () {
      final r = BbbResponse.parse('"0"');
      expect(r.isOk, false);
      expect(r.code, '0');
    });

    test('код 1 → ошибка без data', () {
      final r = BbbResponse.parse('1');
      expect(r.code, '1');
      expect(r.isOk, false);
    });

    test('пустое тело → empty', () {
      final r = BbbResponse.parse('   ');
      expect(r.empty, true);
      expect(r.isOk, false);
    });

    test('пустые кавычки → empty', () {
      final r = BbbResponse.parse('""');
      expect(r.empty, true);
    });
  });
}
