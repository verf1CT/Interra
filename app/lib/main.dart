import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/auth_store.dart';
import 'services/push_service.dart';
import 'screens/biometric_gate.dart';
import 'screens/register_screen.dart';
import 'screens/webview_screen.dart';

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
      builder: (context, child) =>
          BiometricGate(child: child ?? const SizedBox.shrink()),
      home: loggedIn ? const WebViewScreen() : const RegisterScreen(),
    );
  }
}

/// Фирменные цвета Интерры.
const Color kBrandBlue = Color(0xFF3C98D4);
const Color kBrandOrange = Color(0xFFF4752D);

ThemeData _buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandBlue,
    primary: kBrandBlue,
    secondary: kBrandOrange,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF6F7F9),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBrandBlue,
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
        borderSide: const BorderSide(color: kBrandBlue, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kBrandBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
