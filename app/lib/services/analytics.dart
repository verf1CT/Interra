import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// телеметрия приложения: Firebase Analytics (что используют) и Crashlytics
/// (на чём падает). всё best-effort и не бросает: если Firebase не
/// сконфигурирован или сеть недоступна - приложение работает как обычно.
///
/// ВАЖНО: до [enable] (т.е. до успешного `Firebase.initializeApp()`) ни один
/// метод не обращается к Firebase. иначе обращение к `FirebaseAnalytics.instance`
/// в момент построения дерева виджетов уронит `build()` → белый экран
class Analytics {
  /// готовность Firebase. пока false - события молча отбрасываются, а навигатор-
  /// наблюдатель ничего не шлёт
  static bool _ready = false;

  /// доступен только после [enable] - раньше Firebase ещё не создан
  static FirebaseAnalytics get _fa => FirebaseAnalytics.instance;

  /// наблюдатель навигации - шлёт `screen_view` при переходах. безопасен на
  /// любом этапе: до готовности Firebase просто молчит, к Firebase в
  /// конструкторе не обращается (в отличие от FirebaseAnalyticsObserver)
  static final NavigatorObserver observer = _ScreenViewObserver();

  /// включает телеметрию и перехват падений. вызывать ОДИН раз сразу после
  /// успешного `Firebase.initializeApp()`. никогда не бросает
  static Future<void> enable() async {
    _ready = true;
    try {
      // в debug-сборках отчёты не шлём, чтобы не засорять консоль Crashlytics
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);

      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        prevOnError?.call(details);
      };
      // ошибки вне Flutter (асинхронные коллбэки платформы и т.п.)
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      debugPrint('Analytics.enable пропущен: $e');
    }
  }

  /// привязывает события и падения к лицевому счёту (телефону) - чтобы в
  /// Crashlytics было видно, у кого именно проблема
  static Future<void> setUser(String? phone) async {
    if (!_ready) return;
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(phone ?? '');
      await _fa.setUserId(id: phone);
    } catch (e) {
      debugPrint('Analytics.setUser пропущен: $e');
    }
  }

  /// произвольное событие. имена - латиницей в snake_case (требование GA4)
  static Future<void> log(String name, [Map<String, Object>? params]) async {
    if (!_ready) return;
    try {
      await _fa.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('Analytics.log($name) пропущен: $e');
    }
  }

  // --- доменные события -------------------------------------------------------

  static Future<void> cabinetOpened({bool offline = false}) =>
      log('cabinet_opened', {'offline': offline ? 1 : 0});

  static Future<void> loginCompleted() => log('login_completed');

  static Future<void> supportOpened(String channel) =>
      log('support_opened', {'channel': channel});
}

/// логирует `screen_view` по имени маршрута (RouteSettings.name). безымянные
/// маршруты пропускает. к Firebase обращается только через [Analytics.log],
/// который сам молчит, пока телеметрия не включена
class _ScreenViewObserver extends NavigatorObserver {
  void _send(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    Analytics.log('screen_view', {'screen_name': name});
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _send(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _send(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _send(previousRoute);
}
