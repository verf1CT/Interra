import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Биометрический вход (Face ID / Touch ID / отпечаток).
///
/// Опционален: включается пользователем в настройках. Если устройство не
/// поддерживает биометрию — переключатель недоступен, а гейт пропускается.
class Biometric {
  static final _auth = LocalAuthentication();
  static const _kEnabled = 'biometric_enabled';

  /// Доступна ли биометрия на устройстве.
  static Future<bool> get isAvailable async {
    try {
      return (await _auth.isDeviceSupported()) &&
          (await _auth.canCheckBiometrics);
    } catch (e) {
      debugPrint('Biometric.isAvailable: $e');
      return false;
    }
  }

  static Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
  }

  /// Запрашивает подтверждение. true — успех или биометрия не требуется.
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Подтвердите вход в личный кабинет',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // допускаем код-пароль как запасной вариант
        ),
      );
    } catch (e) {
      debugPrint('Biometric.authenticate: $e');
      return false;
    }
  }
}
