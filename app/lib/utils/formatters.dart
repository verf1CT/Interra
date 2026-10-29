import 'package:flutter/services.dart';

/// Форматирует дату при непрерывном вводе цифр:
/// 12122010 -> 12.12.2010 (максимум 8 цифр)
String formatDateTyping(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  if (d.length > 8) d = d.substring(0, 8);
  final b = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    if (i == 2 || i == 4) {
      b.write('.');
    }
    b.write(d[i]);
  }
  return b.toString();
}

/// Форматирует паспорт РФ при непрерывном вводе цифр:
/// 1234123456 -> 1234-123456 (максимум 10 цифр)
String formatPassportTyping(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  if (d.length > 10) d = d.substring(0, 10);
  final b = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    if (i == 4) {
      b.write('-');
    }
    b.write(d[i]);
  }
  return b.toString();
}

/// Вспомогательная функция для обновления позиции курсора с учетом динамических масок
TextEditingValue formatWithDigitsMask(
  TextEditingValue oldValue,
  TextEditingValue newValue,
  String Function(String) formatter,
) {
  final oldText = oldValue.text;
  final newText = newValue.text;
  final cursorPosition = newValue.selection.baseOffset;

  if (cursorPosition < 0) {
    final formatted = formatter(newText);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  // Количество цифр до курсора в новом вводе
  var digitsBeforeCursor = 0;
  for (var i = 0; i < cursorPosition && i < newText.length; i++) {
    if (RegExp(r'\d').hasMatch(newText[i])) {
      digitsBeforeCursor++;
    }
  }

  final formatted = formatter(newText);

  // Находим соответствующую позицию курсора в отформатированном тексте
  var newCursor = 0;
  var digitsCount = 0;
  while (newCursor < formatted.length && digitsCount < digitsBeforeCursor) {
    if (RegExp(r'\d').hasMatch(formatted[newCursor])) {
      digitsCount++;
    }
    newCursor++;
  }

  // Если следующий символ разделитель (точка или дефис) и ввод идет вперед,
  // перешагиваем через него
  if (newCursor < formatted.length &&
      (formatted[newCursor] == '.' || formatted[newCursor] == '-') &&
      newText.length >= oldText.length) {
    newCursor++;
  }

  return TextEditingValue(
    text: formatted,
    selection: TextSelection.collapsed(offset: newCursor.clamp(0, formatted.length)),
  );
}

/// Автоматический форматтер даты ДД.ММ.ГГГГ при вводе цифр
class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return formatWithDigitsMask(oldValue, newValue, formatDateTyping);
  }
}

/// Автоматический форматтер серии и номера паспорта СССС-НННННН при вводе цифр
class PassportInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return formatWithDigitsMask(oldValue, newValue, formatPassportTyping);
  }
}
