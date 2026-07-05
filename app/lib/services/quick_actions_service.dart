import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';
import '../screens/support_screen.dart';
import '../screens/settings_screen.dart';
import 'analytics.dart';

/// быстрые действия по long-press на иконке приложения (iOS 3D-Touch /
/// Android App Shortcuts): «Главная», «Поддержка», «Настройки».
///
/// Навигацию выполняем через общий [navigatorKey], поэтому переход работает и
/// при холодном старте (ярлык запустил приложение), и когда оно уже открыто
class QuickActionsService {
  /// ключ навигатора приложения - задаётся в `MaterialApp.navigatorKey`
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const _typeHome = 'action_home';
  static const _typePay = 'action_pay';
  static const _typeSupport = 'action_support';
  static const _typeSettings = 'action_settings';

  static const QuickActions _qa = QuickActions();

  /// сигналы экрану кабинета (счётчики-тики): открыть главную / пополнение
  static final ValueNotifier<int> homeRequested = ValueNotifier<int>(0);
  static final ValueNotifier<int> paymentRequested = ValueNotifier<int>(0);

  /// действие, пришедшее до готовности навигатора (холодный старт по ярлыку)
  static String? _pending;

  static Future<void> init() async {
    try {
      _qa.initialize(route);
      // без кастомных icon: именованные ресурсы пришлось бы класть в каждую
      // платформу, а их отсутствие роняет setShortcutItems. системного вида
      // ярлыков достаточно
      // иконки: iOS - template-картинки из Assets.xcassets, Android - drawable
      await _qa.setShortcutItems(const [
        ShortcutItem(
            type: _typeHome, localizedTitle: 'Личный кабинет', icon: 'qa_home'),
        ShortcutItem(type: _typePay, localizedTitle: 'Пополнить', icon: 'qa_pay'),
        ShortcutItem(
            type: _typeSupport,
            localizedTitle: 'Поддержка',
            icon: 'qa_support'),
        ShortcutItem(
            type: _typeSettings,
            localizedTitle: 'Настройки',
            icon: 'qa_settings'),
      ]);
    } catch (e) {
      debugPrint('QuickActions.init пропущен: $e');
    }
  }

  /// выполняет переход по типу ярлыка. если навигатор ещё не готов (самый
  /// ранний кадр холодного старта) - запоминаем и повторяем после первого кадра
  static void route(String type) {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      _pending = type;
      WidgetsBinding.instance.addPostFrameCallback((_) => _flush());
      return;
    }
    Analytics.log('quick_action', {'type': type});
    switch (type) {
      case _typeHome:
        // к корню и открыть главную (Основную информацию), а не последний раздел
        nav.popUntil((r) => r.isFirst);
        homeRequested.value++;
        break;
      case _typePay:
        // к корню (кабинету) и просим открыть раздел пополнения
        nav.popUntil((r) => r.isFirst);
        paymentRequested.value++;
        break;
      case _typeSupport:
        nav.push(MaterialPageRoute(
          builder: (_) => const SupportScreen(),
          settings: const RouteSettings(name: 'support'),
        ));
        break;
      case _typeSettings:
        nav.push(MaterialPageRoute(
          builder: (_) => const SettingsScreen(),
          settings: const RouteSettings(name: 'settings'),
        ));
        break;
    }
  }

  static void _flush() {
    final type = _pending;
    if (type == null) return;
    if (navigatorKey.currentState == null) {
      // навигатор всё ещё не готов - пробуем на следующем кадре
      WidgetsBinding.instance.addPostFrameCallback((_) => _flush());
      return;
    }
    _pending = null;
    route(type);
  }
}
