import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/utils/phone.dart';

void main() {
  group('normalizeRuPhone', () {
    test('10 цифр (ввод с префиксом +7) → 7XXXXXXXXXX', () {
      expect(normalizeRuPhone('9229999999'), '79229999999');
    });

    test('форматированный ввод 922 999-99-99 → 79229999999', () {
      expect(normalizeRuPhone('922 999-99-99'), '79229999999');
    });

    test('номер с 8 → 7', () {
      expect(normalizeRuPhone('89229999999'), '79229999999');
    });

    test('уже с +7 остаётся 11 цифр', () {
      expect(normalizeRuPhone('+7 922 999 99 99'), '79229999999');
    });

    test('неполный ввод возвращается как цифры (вызывающий проверит длину)', () {
      expect(normalizeRuPhone('922'), '922');
    });
  });

  group('formatRuPhoneTyping', () {
    test('полный номер форматируется как 922 999-99-99', () {
      expect(formatRuPhoneTyping('9229999999'), '922 999-99-99');
    });

    test('частичный ввод', () {
      expect(formatRuPhoneTyping('9229'), '922 9');
      expect(formatRuPhoneTyping('922999'), '922 999');
      expect(formatRuPhoneTyping('92299999'), '922 999-99');
    });

    test('лишние цифры обрезаются до 10', () {
      expect(formatRuPhoneTyping('922999999999'), '922 999-99-99');
    });

    test('нецифры игнорируются', () {
      expect(formatRuPhoneTyping('(922) 999'), '922 999');
    });
  });

  group('formatRuPhoneFull', () {
    test('11 цифр → +7 922 999-99-99', () {
      expect(formatRuPhoneFull('79229999999'), '+7 922 999-99-99');
    });

    test('null → прочерк', () {
      expect(formatRuPhoneFull(null), '—');
    });

    test('некорректная длина возвращается как есть', () {
      expect(formatRuPhoneFull('123'), '123');
    });
  });
}
