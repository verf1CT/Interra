import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/auth_store.dart';
import 'services/push_service.dart';
import 'screens/login_screen.dart';
import 'screens/webview_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase не инициализирован (это нормально без конфигурации): $e');
  }

  final hasCreds = await AuthStore().hasCredentials;

  // Интерфейс показываем СРАЗУ — не ждём пуши.
  runApp(InterraApp(loggedIn: hasCreds));

  // Push-инициализация в фоне: не блокирует UI и безопасна без APNs/бэкенда
  // (на iOS без APNs getToken может висеть/падать — это нормально).
  if (firebaseReady) {
    PushService.init();
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
