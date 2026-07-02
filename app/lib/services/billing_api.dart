import 'dart:math';
import 'package:flutter/foundation.dart';
import '../config.dart';
import 'secure_http.dart';

/// результат запроса к биллингу `bbb`.
///
/// Ответы приходят как JSON-строка в двойных кавычках (например `"178…"`),
/// поэтому кавычки снимаются. полезная нагрузка (токен `app` или ссылка
/// `?login=…`) лежит в [data]; коды ошибок `0`/`1` - в [code]; пустое тело
/// (общая ошибка данных/синтаксиса) - [empty]; сетевой сбой - [networkError]
class BbbResponse {
  final String? data;
  final String? code; // '0' или '1'
  final bool empty;
  final bool networkError;

  const BbbResponse({
    this.data,
    this.code,
    this.empty = false,
    this.networkError = false,
  });

  bool get isOk => data != null;

  /// разбирает тело ответа `bbb`. снимает обрамляющие кавычки и пробелы
  /// (`"178…"` → `178…`); `0`/`1` - коды ошибок; пустое тело - [empty]
  factory BbbResponse.parse(String body) {
    var s = body.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.isEmpty) return const BbbResponse(empty: true);
    if (s == '0' || s == '1') return BbbResponse(code: s);
    return BbbResponse(data: s);
  }
}

/// клиент штатного API биллинга UTM5 (`bbb`): регистрация приложения по SMS
/// один раз и получение ссылки на личный кабинет при каждом открытии
class BillingApi {
  static final _rnd = Random.secure();

  static Future<BbbResponse> _call({
    required String cmd,
    String? app,
    String? num,
  }) async {
    final uri = Uri.parse(AppConfig.bbbUrl).replace(queryParameters: {
      'cmd': cmd,
      if (app != null) 'app': app,
      if (num != null) 'num': num,
    });
    try {
      final res =
          await SecureHttp.get(uri).timeout(const Duration(seconds: 20));
      return BbbResponse.parse(res.body);
    } catch (e) {
      debugPrint('BillingApi.$cmd сетевой сбой: $e');
      return const BbbResponse(networkError: true);
    }
  }

  static String _random15() {
    final b = StringBuffer();
    for (var i = 0; i < 15; i++) {
      b.write(_rnd.nextInt(10));
    }
    return b.toString();
  }

  /// шаг 1 - первичная регистрация: `cmd=set&app={15 случайных цифр}`.
  /// Возвращает 24-значный токен приложения (`app`) или null при ошибке
  static Future<String?> registerPrimary() async {
    final r = await _call(cmd: 'set', app: _random15());
    return r.isOk ? r.data : null;
  }

  /// шаг 2 - запрос SMS: `cmd=get&num={телефон}&app={app}`.
  /// isOk - код отправлен; code '1' - нет привязанного телефона в биллинге;
  /// code '0' - нет первичной регистрации
  static Future<BbbResponse> requestSms(String phone, String app) =>
      _call(cmd: 'get', num: phone, app: app);

  /// шаг 3 - подтверждение кодом: `cmd=set&num={код}&app={app}`.
  /// isOk - приложение занесено в базу; code '1' - нет первичной регистрации;
  /// code '0' - код не совпал
  static Future<BbbResponse> confirmSms(String code, String app) =>
      _call(cmd: 'set', num: code, app: app);

  /// удаление регистрации: `cmd=del&app={app}`. best-effort, ошибку не проверяет
  static Future<void> deleteApp(String app) async {
    await _call(cmd: 'del', app: app);
  }

  /// получение ссылки на ЛК: `cmd=open&app={app}`.
  /// isOk - data содержит `?login=…` (ссылка живёт ~30 минут);
  /// code '1' - телефон приложения отвязан от ЛК; code '0' - приложение
  /// не зарегистрировано в биллинге
  static Future<BbbResponse> openCabinet(String app) =>
      _call(cmd: 'open', app: app);
}
