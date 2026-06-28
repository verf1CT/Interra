import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Защищённое хранилище учётных данных абонента (для авто-логина в UTM5).
/// На Android использует EncryptedSharedPreferences, на iOS — Keychain.
class AuthStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kLogin = 'utm5_login';
  static const _kPassword = 'utm5_password';

  Future<void> save(String login, String password) async {
    await _storage.write(key: _kLogin, value: login);
    await _storage.write(key: _kPassword, value: password);
  }

  Future<({String login, String password})?> read() async {
    final login = await _storage.read(key: _kLogin);
    final password = await _storage.read(key: _kPassword);
    if (login == null || password == null) return null;
    return (login: login, password: password);
  }

  Future<String?> get login => _storage.read(key: _kLogin);

  Future<bool> get hasCredentials async => (await read()) != null;

  Future<void> clear() async {
    await _storage.delete(key: _kLogin);
    await _storage.delete(key: _kPassword);
  }
}
