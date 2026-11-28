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
      return parseResponse(res.statusCode, jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (_) {
      return const PayLink();
    }
  }

  /// сайт берёт form_url при любом успешном статусе (сейчас отвечает не 200),
  /// поэтому проверяем 2xx, иначе ссылка банка уходила в текст ошибки
  static PayLink parseResponse(int status, Object? data) {
    // успех без ссылки - пусть откроется форма сайта, а не ошибка
    if (status >= 200 && status < 300) {
      final url = data is Map ? data['form_url'] : null;
      return url is String && url.startsWith('https://') ? PayLink(url: url) : const PayLink();
    }
    return PayLink(error: parseError(data));
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
