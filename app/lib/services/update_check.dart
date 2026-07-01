import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Проверка новой версии приложения.
///
/// Пока приложения нет в сторах, обновления ставятся вручную — поэтому
/// сравниваем свою версию с `version:` из pubspec.yaml в main-ветке GitHub.
/// Когда появятся сторы, эту проверку заменит их механизм обновлений.
class UpdateCheck {
  static const _pubspecUrl =
      'https://raw.githubusercontent.com/verf1CT/Interra/main/app/pubspec.yaml';

  /// Свежая версия из репозитория, если она новее установленной, иначе null.
  static final ValueNotifier<String?> available = ValueNotifier(null);

  /// Разовая проверка (вызывается при старте, best-effort).
  static Future<void> run() async {
    try {
      final res = await http
          .get(Uri.parse(_pubspecUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final m = RegExp(r'^version:\s*([\d.]+)', multiLine: true)
          .firstMatch(res.body);
      final latest = m?.group(1);
      if (latest == null) return;
      if (isNewer(latest, AppConfig.appVersion)) {
        available.value = latest;
      }
    } catch (e) {
      debugPrint('UpdateCheck пропущен: $e');
    }
  }

  /// true, если [latest] строго новее [current] (сравнение по числам через точку).
  @visibleForTesting
  static bool isNewer(String latest, String current) {
    final a = latest.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final b = current.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
