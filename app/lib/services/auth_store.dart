import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// защищённое хранилище регистрации приложения в биллинге UTM5.
/// На Android использует EncryptedSharedPreferences, на iOS - Keychain.
///
/// Схема `bbb`: один раз регистрируем приложение по SMS и храним 24-значный
/// токен [appToken]; телефон [phone] сохраняется после подтверждения кодом
class AuthStore {
  // v10: шифрование на Android включено по умолчанию, параметр не нужен
  static const _storage = FlutterSecureStorage();

  static const _kAppToken = 'billing_app_token';
  static const _kPhone = 'billing_phone';

  /// токен приложения (24 цифры). появляется уже после первичной регистрации,
  /// до подтверждения SMS - поэтому сам по себе ещё не значит «зарегистрирован»
  Future<String?> get appToken => _storage.read(key: _kAppToken);
  Future<void> saveAppToken(String token) =>
      _storage.write(key: _kAppToken, value: token);

  /// телефон абонента. сохраняется только после успешного подтверждения кодом
  Future<String?> get phone => _storage.read(key: _kPhone);
  Future<void> savePhone(String phone) =>
      _storage.write(key: _kPhone, value: phone);

  /// регистрация завершена: есть и токен, и подтверждённый телефон
  Future<bool> get isRegistered async =>
      (await appToken) != null && (await phone) != null;

  Future<void> clear() async {
    await _storage.delete(key: _kAppToken);
    await _storage.delete(key: _kPhone);
  }
}
