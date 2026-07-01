import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Код-пароль (PIN из 4 цифр) — альтернатива биометрии.
///
/// Храним не сам PIN, а его SHA-256 с солью, в защищённом хранилище системы
/// (Keychain / EncryptedSharedPreferences) — как и токен биллинга в AuthStore.
class PinLock {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kHash = 'pin_hash';
  static const _kSalt = 'pin_salt';

  static const int length = 4;

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// Установлен ли PIN.
  static Future<bool> get isSet async =>
      (await _storage.read(key: _kHash)) != null;

  /// Устанавливает (или меняет) PIN.
  static Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt =
        base64UrlEncode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await _storage.write(key: _kSalt, value: salt);
    await _storage.write(key: _kHash, value: _hash(pin, salt));
  }

  /// Проверяет введённый PIN.
  static Future<bool> verify(String pin) async {
    final hash = await _storage.read(key: _kHash);
    final salt = await _storage.read(key: _kSalt);
    if (hash == null || salt == null) return false;
    return _hash(pin, salt) == hash;
  }

  /// Убирает PIN (выход из аккаунта / отключение в настройках).
  static Future<void> clear() async {
    await _storage.delete(key: _kHash);
    await _storage.delete(key: _kSalt);
  }
}
