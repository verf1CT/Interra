import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'theme.dart';
import 'services/auth_store.dart';
import 'services/push_service.dart';
import 'services/analytics.dart';
import 'services/quick_actions_service.dart';
import 'screens/biometric_gate.dart';
import 'screens/register_screen.dart';
import 'screens/webview_screen.dart';
import 'widgets/privacy_shield.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool registered = false;
  try {
    registered = await AuthStore().isRegistered;
  } catch (e) {
    debugPrint('Чтение регистрации не удалось: $e');
  }

  // Интерфейс показываем ПЕРВЫМ ДЕЛОМ — ничто не должно блокировать первый кадр.
  // Биометрический замок навешивает BiometricGate (через MaterialApp.builder).
  runApp(InterraApp(loggedIn: registered));

  // Firebase, телеметрия и push — полностью в фоне и с таймаутом, чтобы
  // инициализация (особенно на iOS без APNs) никогда не подвешивала запуск.
  _initServices();
}

Future<void> _initServices() async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    await Analytics.enable();
    Analytics.setUser(await AuthStore().phone);
    await PushService.init();
  } catch (e) {
    debugPrint('Firebase/телеметрия/push не инициализированы (ок без конфигурации): $e');
  }
  // Быстрые действия от Firebase не зависят — настраиваем отдельно.
  await QuickActionsService.init();
}

class InterraApp extends StatelessWidget {
  final bool loggedIn;
  const InterraApp({super.key, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ЛК Интерра',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorKey: QuickActionsService.navigatorKey,
      navigatorObservers: [Analytics.observer],
      // Порядок важен: PrivacyShield снаружи — закрывает в том числе экран
      // блокировки, когда приложение уходит в фон (снимок переключателя задач).
      builder: (context, child) => PrivacyShield(
        child: BiometricGate(child: child ?? const SizedBox.shrink()),
      ),
      home: loggedIn ? const WebViewScreen() : const RegisterScreen(),
    );
  }
}
