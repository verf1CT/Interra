// Утилиты для российского номера телефона. Вынесены отдельно, чтобы быть
// чистыми и покрытыми юнит-тестами (см. test/phone_test.dart).

/// Только цифры из строки.
String digitsOf(String input) => input.replaceAll(RegExp(r'\D'), '');

/// Приводит ввод к 11-значному виду `7XXXXXXXXXX`:
/// - `8XXXXXXXXXX` → `7XXXXXXXXXX`;
/// - 10 цифр (ввод без кода страны, с префиксом «+7») → `7` + 10 цифр;
/// - иначе возвращает как есть (цифрами) — вызывающий проверит длину.
String normalizeRuPhone(String input) {
  var d = digitsOf(input);
  if (d.length == 11 && d.startsWith('8')) d = '7${d.substring(1)}';
  if (d.length == 10) d = '7$d';
  return d;
}

/// Форматирует ввод (до 10 цифр, без кода страны) как `922 999-99-99`.
String formatRuPhoneTyping(String input) {
  var d = digitsOf(input);
  if (d.length > 10) d = d.substring(0, 10);
  final b = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    if (i == 3 || i == 6 || i == 8) b.write(i == 3 ? ' ' : '-');
    b.write(d[i]);
  }
  return b.toString();
}

/// Форматирует сохранённый 11-значный номер `79229999999` → `+7 922 999-99-99`.
/// Если длина не 11 — возвращает исходную строку (или прочерк).
String formatRuPhoneFull(String? phone) {
  final d = digitsOf(phone ?? '');
  if (d.length != 11) return phone ?? '—';
  return '+${d[0]} ${d.substring(1, 4)} ${d.substring(4, 7)}-'
      '${d.substring(7, 9)}-${d.substring(9)}';
}
