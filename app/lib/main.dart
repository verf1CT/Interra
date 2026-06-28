import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/auth_store.dart';
import 'services/push_service.dart';
import 'screens/login_screen.dart';
import 'screens/webview_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Push-инициализация необязательна: если Firebase не сконфигурирован
  // (нет google-services.json / firebase_options.dart), приложение всё равно
  // запускается — WebView и авто-логин работают, push включится после настройки.
  try {
    await Firebase.initializeApp();
    await PushService.init();
  } catch (e) {
    debugPrint('Firebase/push не инициализирован (это нормально без конфигурации): $e');
  }

  final hasCreds = await AuthStore().hasCredentials;
  runApp(InterraApp(loggedIn: hasCreds));
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
