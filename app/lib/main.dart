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
      theme: _buildTheme(),
      home: loggedIn ? const WebViewScreen() : const LoginScreen(),
    );
  }
}

const Color kBrandRed = Color(0xFFE3000F);

ThemeData _buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandRed,
    primary: kBrandRed,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF6F7F9),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBrandRed,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF2F3F5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBrandRed, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kBrandRed,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
