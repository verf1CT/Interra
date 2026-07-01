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
  static const _kLastUnlock = 'lock_last_unlock_ms';

  /// Льготный период: после успешной разблокировки повторно не спрашиваем
  /// полчаса. Баланс — данные личные, но не банковские; каждый вход
  /// запрашивать — слишком назойливо.
  static const Duration gracePeriod = Duration(minutes: 30);

  /// Отмечает успешную разблокировку (биометрией или PIN) — от этого момента
  /// отсчитывается льготный период.
  static Future<void> markUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastUnlock, DateTime.now().millisecondsSinceEpoch);
  }

  /// true — льготный период ещё действует, замок можно не показывать.
  static Future<bool> get withinGracePeriod async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kLastUnlock);
    if (last == null) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    // Отрицательное elapsed (перевод часов назад) считаем истёкшим.
    return elapsed >= 0 && elapsed < gracePeriod.inMilliseconds;
  }

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
        biometricOnly: false, // допускаем код-пароль как запасной вариант
        persistAcrossBackgrounding: true, // бывший stickyAuth
      );
    } catch (e) {
      debugPrint('Biometric.authenticate: $e');
      return false;
    }
  }
}
