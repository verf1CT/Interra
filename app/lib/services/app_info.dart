import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// версия приложения - ЕДИНЫЙ источник: нативный пакет, куда `version:` из
/// pubspec.yaml попадает при сборке (CFBundleShortVersionString на iOS,
/// versionName на Android). так номер не приходится дублировать в коде.
///
/// [load] вызывается один раз при старте; до этого [version] отдаёт запасное
/// значение (совпадает с pubspec) - на случай раннего обращения или сбоя канала
class AppInfo {
  static String version = '1.0.0';

  static Future<void> load() async {
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (e) {
      debugPrint('AppInfo.load пропущен (оставляем запасную версию): $e');
    }
  }
}
