import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/utils/formatters.dart';

void main() {
  group('formatDateTyping', () {
    test('formats digits step by step and handles 12122010 -> 12.12.2010', () {
      expect(formatDateTyping(''), '');
      expect(formatDateTyping('1'), '1');
      expect(formatDateTyping('12'), '12');
      expect(formatDateTyping('121'), '12.1');
      expect(formatDateTyping('1212'), '12.12');
      expect(formatDateTyping('12122'), '12.12.2');
      expect(formatDateTyping('121220'), '12.12.20');
      expect(formatDateTyping('1212201'), '12.12.201');
      expect(formatDateTyping('12122010'), '12.12.2010');
      expect(formatDateTyping('12122010999'), '12.12.2010');
    });

    test('normalizes existing separators', () {
      expect(formatDateTyping('12/12/2010'), '12.12.2010');
      expect(formatDateTyping('12-12-2010'), '12.12.2010');
      expect(formatDateTyping('12.12.2010'), '12.12.2010');
    });
  });

  group('formatPassportTyping', () {
    test('formats digits step by step and handles 1234123456 -> 1234-123456', () {
      expect(formatPassportTyping(''), '');
      expect(formatPassportTyping('1'), '1');
      expect(formatPassportTyping('12'), '12');
      expect(formatPassportTyping('123'), '123');
      expect(formatPassportTyping('1234'), '1234');
      expect(formatPassportTyping('12341'), '1234-1');
      expect(formatPassportTyping('123412'), '1234-12');
      expect(formatPassportTyping('1234123456'), '1234-123456');
      expect(formatPassportTyping('12341123456'), '1234-112345');
    });

    test('normalizes spaces and hyphens', () {
      expect(formatPassportTyping('1234 123456'), '1234-123456');
      expect(formatPassportTyping('1234-123456'), '1234-123456');
    });
  });

  group('InputFormatters', () {
    test('DateInputFormatter formats update correctly and advances cursor', () {
      final formatter = DateInputFormatter();
      final res = formatter.formatEditUpdate(
        const TextEditingValue(text: '12', selection: TextSelection.collapsed(offset: 2)),
        const TextEditingValue(text: '121', selection: TextSelection.collapsed(offset: 3)),
      );
      expect(res.text, '12.1');
      expect(res.selection.baseOffset, 4);
    });

    test('PassportInputFormatter formats update correctly and advances cursor past hyphen', () {
      final formatter = PassportInputFormatter();
      final res = formatter.formatEditUpdate(
        const TextEditingValue(text: '1234', selection: TextSelection.collapsed(offset: 4)),
        const TextEditingValue(text: '12345', selection: TextSelection.collapsed(offset: 5)),
      );
      expect(res.text, '1234-5');
      expect(res.selection.baseOffset, 6);
    });
  });
}
