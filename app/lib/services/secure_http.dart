import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// HTTP-клиент с закреплением корневого сертификата (certificate pinning).
///
/// Доверяем корням GlobalSign (GlobalSign Root CA - R3), которыми подписаны
/// боевые сервисы Интерры (*.interra.ru, stat.interra.ru, push.interra.ru),
/// а также Let's Encrypt (ISRG Root X1/X2). Это блокирует подмену сертификата
/// на враждебном Wi-Fi (MITM с чужим корневым центром): даже валидный с точки
/// зрения системы сертификат, но выданный другим CA, будет отклонён.
///
/// Пинуем именно КОРЕНЬ (не промежуточный и не лист): корни стабильны годами.
/// Если Интерра сменит удостоверяющий центр - добавить его корень в assets/certs
/// и в [_pinnedRoots].
///
/// Применяется только к нашим хостам (биллинг, бэкенд). сторонние хосты
/// (спидтест Cloudflare, проверка версии на GitHub) ходят обычным клиентом
class SecureHttp {
  static const _pinnedRoots = [
    'assets/certs/globalsign-r3.pem',
    'assets/certs/isrgrootx1.pem',
    'assets/certs/isrg-root-x2.pem',
  ];

  static http.Client? _client;
  static bool _tried = false;

  /// ленивая инициализация. если пиннинг настроить не удалось (например, ассет
  /// не загрузился) - откатываемся на обычный клиент, чтобы не «окирпичить»
  /// приложение: недоступность ассета это ошибка сборки, а не атака
  static Future<http.Client> _pinned() async {
    if (_client != null) return _client!;
    if (_tried) return _client ??= http.Client();
    _tried = true;
    try {
      if (kIsWeb) return _client = http.Client();
      final ctx = SecurityContext(withTrustedRoots: false);
      for (final path in _pinnedRoots) {
        final data = await rootBundle.load(path);
        ctx.setTrustedCertificatesBytes(data.buffer.asUint8List());
      }
      _client = IOClient(HttpClient(context: ctx));
    } catch (e) {
      debugPrint('SecureHttp: пиннинг не настроен, обычный клиент: $e');
      _client = http.Client();
    }
    return _client!;
  }

  static Future<http.Response> get(Uri url) async =>
      (await _pinned()).get(url);

  static Future<http.Response> post(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      (await _pinned()).post(url, headers: headers, body: body);
}
