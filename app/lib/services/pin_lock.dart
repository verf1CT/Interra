import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// код-пароль (PIN из 4 цифр) - альтернатива биометрии.
///
/// Храним не сам PIN, а его SHA-256 с солью, в защищённом хранилище системы
/// (Keychain / EncryptedSharedPreferences) - как и токен биллинга в AuthStore
class PinLock {
  // v10: шифрование на Android включено по умолчанию, параметр не нужен
  static const _storage = FlutterSecureStorage();

  static const _kHash = 'pin_hash';
  static const _kSalt = 'pin_salt';
  static const _kFails = 'pin_fails';
  static const _kLockUntil = 'pin_lock_until_ms';

  static const int length = 4;

  /// защита от перебора: после [maxAttempts] неверных вводов подряд -
  /// пауза [cooldown], в течение которой любой ввод отклоняется
  static const int maxAttempts = 5;
  static const Duration cooldown = Duration(seconds: 30);

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// установлен ли PIN
  static Future<bool> get isSet async =>
      (await _storage.read(key: _kHash)) != null;

  /// устанавливает (или меняет) PIN
  static Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt =
        base64UrlEncode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await _storage.write(key: _kSalt, value: salt);
    await _storage.write(key: _kHash, value: _hash(pin, salt));
  }

  /// сколько осталось ждать до следующей попытки (Duration.zero - можно вводить)
  static Future<Duration> get cooldownRemaining async {
    final raw = await _storage.read(key: _kLockUntil);
    final until = int.tryParse(raw ?? '');
    if (until == null) return Duration.zero;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? Duration(milliseconds: left) : Duration.zero;
  }

  /// проверяет введённый PIN (с учётом паузы после серии неверных вводов)
  static Future<bool> verify(String pin) async {
    if ((await cooldownRemaining) > Duration.zero) return false;
    final hash = await _storage.read(key: _kHash);
    final salt = await _storage.read(key: _kSalt);
    if (hash == null || salt == null) return false;

    if (_hash(pin, salt) == hash) {
      await _storage.delete(key: _kFails);
      await _storage.delete(key: _kLockUntil);
      return true;
    }

    final fails = (int.tryParse(await _storage.read(key: _kFails) ?? '') ?? 0) + 1;
    if (fails >= maxAttempts) {
      await _storage.write(
        key: _kLockUntil,
        value: (DateTime.now().millisecondsSinceEpoch +
                cooldown.inMilliseconds)
            .toString(),
      );
      await _storage.delete(key: _kFails);
    } else {
      await _storage.write(key: _kFails, value: fails.toString());
    }
    return false;
  }

  /// убирает PIN (выход из аккаунта / отключение в настройках)
  static Future<void> clear() async {
    await _storage.delete(key: _kHash);
    await _storage.delete(key: _kSalt);
    await _storage.delete(key: _kFails);
    await _storage.delete(key: _kLockUntil);
  }
}
