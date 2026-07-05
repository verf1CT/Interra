import 'dart:convert';
import 'dart:io' show Platform;
import '../config.dart';
import 'app_info.dart';
import 'secure_http.dart';

/// клиент нашего бэкенда (server/): регистрация устройства для push-рассылок
class ApiClient {
  /// привязывает push-токен к устройству и (опционально) к логину абонента
  static Future<bool> registerDevice({
    required String token,
    String? clientLogin,
    List<String>? segments,
    Map<String, dynamic>? prefs,
  }) async {
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/api/devices/register');
    try {
      final res = await SecureHttp
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': token,
              'clientLogin': clientLogin,
              'platform': Platform.isIOS ? 'ios' : 'android',
              'appVersion': AppInfo.version,
              if (segments != null) 'segments': segments,
              if (prefs != null) 'prefs': prefs,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      // сеть недоступна - не критично, попробуем при следующем запуске
      return false;
    }
  }

  static Future<void> unregisterDevice(String token) async {
    final uri = Uri.parse('${AppConfig.backendBaseUrl}/api/devices/unregister');
    try {
      await SecureHttp
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}
