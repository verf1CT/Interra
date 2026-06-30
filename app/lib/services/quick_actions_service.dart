import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';
import '../screens/support_screen.dart';
import '../screens/settings_screen.dart';
import 'analytics.dart';

/// Быстрые действия по long-press на иконке приложения (iOS 3D-Touch /
/// Android App Shortcuts): «Главная», «Поддержка», «Настройки».
///
/// Навигацию выполняем через общий [navigatorKey], поэтому переход работает и
/// при холодном старте (ярлык запустил приложение), и когда оно уже открыто.
class QuickActionsService {
  /// Ключ навигатора приложения — задаётся в `MaterialApp.navigatorKey`.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const _typeHome = 'action_home';
  static const _typeSupport = 'action_support';
  static const _typeSettings = 'action_settings';

  static const QuickActions _qa = QuickActions();

  /// Действие, пришедшее до готовности навигатора (холодный старт по ярлыку).
  static String? _pending;

  static Future<void> init() async {
    try {
      _qa.initialize(route);
      // Без кастомных icon: именованные ресурсы пришлось бы класть в каждую
      // платформу, а их отсутствие роняет setShortcutItems. Системного вида
      // ярлыков достаточно.
      await _qa.setShortcutItems(const [
        ShortcutItem(type: _typeHome, localizedTitle: 'Личный кабинет'),
        ShortcutItem(type: _typeSupport, localizedTitle: 'Поддержка'),
        ShortcutItem(type: _typeSettings, localizedTitle: 'Настройки'),
      ]);
    } catch (e) {
      debugPrint('QuickActions.init пропущен: $e');
    }
  }

  /// Выполняет переход по типу ярлыка. Если навигатор ещё не готов (самый
  /// ранний кадр холодного старта) — запоминаем и повторяем после первого кадра.
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
        // Возврат к корню (кабинету), закрыв вложенные экраны.
        nav.popUntil((r) => r.isFirst);
        break;
      case _typeSupport:
        nav.push(MaterialPageRoute(builder: (_) => const SupportScreen()));
        break;
      case _typeSettings:
        nav.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        break;
    }
  }

  static void _flush() {
    final type = _pending;
    if (type == null) return;
    if (navigatorKey.currentState == null) {
      // Навигатор всё ещё не готов — пробуем на следующем кадре.
      WidgetsBinding.instance.addPostFrameCallback((_) => _flush());
      return;
    }
    _pending = null;
    route(type);
  }
}
