import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/auth_store.dart';
import 'services/push_service.dart';
import 'screens/login_screen.dart';
import 'screens/webview_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool hasCreds = false;
  try {
    hasCreds = await AuthStore().hasCredentials;
  } catch (e) {
    debugPrint('Чтение учётных данных не удалось: $e');
  }

  // Интерфейс показываем ПЕРВЫМ ДЕЛОМ — ничто не должно блокировать первый кадр.
  runApp(InterraApp(loggedIn: hasCreds));

  // Firebase и push — полностью в фоне и с таймаутом, чтобы инициализация
  // (особенно на iOS без APNs) никогда не подвешивала запуск приложения.
  _initFirebaseAndPush();
}

Future<void> _initFirebaseAndPush() async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    await PushService.init();
  } catch (e) {
    debugPrint('Firebase/push не инициализированы (ок без конфигурации): $e');
  }
}

class InterraApp extends StatelessWidget {
  final bool loggedIn;
  const InterraApp({super.key, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ЛК Интерра',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFE3000F),
        useMaterial3: true,
      ),
      home: loggedIn ? const WebViewScreen() : const LoginScreen(),
    );
  }
}
