import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Телеметрия приложения: Firebase Analytics (что используют) и Crashlytics
/// (на чём падает). Всё best-effort и не бросает: если Firebase не
/// сконфигурирован или сеть недоступна — приложение работает как обычно.
class Analytics {
  static final FirebaseAnalytics _fa = FirebaseAnalytics.instance;

  /// Наблюдатель навигации — автоматически шлёт `screen_view` при переходах.
  /// Подключается в `MaterialApp.navigatorObservers`.
  static final FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: _fa);

  /// Перехват необработанных ошибок Flutter и зоны → Crashlytics.
  /// Вызывать один раз после Firebase.initializeApp(). Никогда не бросает.
  static Future<void> initCrashReporting() async {
    try {
      // В debug-сборках отчёты не шлём, чтобы не засорять консоль Crashlytics.
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);

      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        prevOnError?.call(details);
      };
      // Ошибки вне Flutter (асинхронные коллбэки платформы и т.п.).
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      debugPrint('Analytics.initCrashReporting пропущен: $e');
    }
  }

  /// Привязывает события и падения к лицевому счёту (телефону) — чтобы в
  /// Crashlytics было видно, у кого именно проблема. Без хранения ПДн на сервере
  /// аналитики сверх самого идентификатора.
  static Future<void> setUser(String? phone) async {
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(phone ?? '');
      await _fa.setUserId(id: phone);
    } catch (e) {
      debugPrint('Analytics.setUser пропущен: $e');
    }
  }

  /// Произвольное событие. Имена — латиницей в snake_case (требование GA4).
  static Future<void> log(String name, [Map<String, Object>? params]) async {
    try {
      await _fa.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('Analytics.log($name) пропущен: $e');
    }
  }

  // --- Доменные события -------------------------------------------------------

  static Future<void> cabinetOpened({bool offline = false}) =>
      log('cabinet_opened', {'offline': offline ? 1 : 0});

  static Future<void> loginCompleted() => log('login_completed');

  static Future<void> supportOpened(String channel) =>
      log('support_opened', {'channel': channel});
}
