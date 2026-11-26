import 'dart:convert';

import 'secure_http.dart';

/// результат запроса ссылки на оплату: либо адрес страницы банка, либо
/// текст ошибки от сайта (неверный счёт, сумма), либо сеть недоступна
class PayLink {
  final String? url;
  final String? error;
  const PayLink({this.url, this.error});
}

/// оплата картой через сайт Интерры: форма на interra.ru/sberbank/ шлёт
/// счёт и сумму в /api/v1/billingpay/ и получает form_url страницы банка.
/// делаем тот же запрос сами, чтобы абонент сразу попадал на страницу оплаты
class SitePay {
  static const _endpoint = 'https://interra.ru/api/v1/billingpay/';

  /// запасной путь, если сайт не ответил: страница оплаты с подставленным счётом
  static String fallbackUrl(String account) => account.isEmpty
      ? 'https://interra.ru/sberbank/'
      : 'https://interra.ru/sberbank/?epay=$account';

  static Future<PayLink> request(String account, int amount) async {
    try {
      final res = await SecureHttp.post(
        Uri.parse(_endpoint),
        body: {'epay': account, 'amount': '$amount'},
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200 && data is Map && data['form_url'] is String) {
        final url = data['form_url'] as String;
        if (url.startsWith('https://')) return PayLink(url: url);
      }
      return PayLink(error: parseError(data));
    } catch (_) {
      return const PayLink();
    }
  }

  /// {"epay": ["..."], "amount": ["..."], "detail": "..."} -> одна строка
  static String? parseError(Object? data) {
    if (data is! Map) return null;
    final parts = <String>[];
    for (final v in data.values) {
      if (v is List) parts.addAll(v.whereType<String>());
      if (v is String) parts.add(v);
    }
    return parts.isEmpty ? null : parts.join('. ');
  }
}
