import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_store.dart';
import '../services/api_client.dart';
import '../services/billing_api.dart';
import '../services/biometric.dart';
import 'register_screen.dart';

const Color _brand = Color(0xFF3C98D4); // фирменный синий Интерры

/// Экран настроек: аккаунт, уведомления, выход.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _phone;
  bool _notifications = true;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final phone = await AuthStore().phone;
    final prefs = await SharedPreferences.getInstance();
    final bioAvail = await Biometric.isAvailable;
    final bioOn = await Biometric.isEnabled;
    setState(() {
      _phone = phone;
      _notifications = prefs.getBool('notifications_enabled') ?? true;
      _biometricAvailable = bioAvail;
      _biometricEnabled = bioOn;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    // Включение защищаем проверкой биометрии — чтобы случайный человек
    // не включил замок чужим лицом/пальцем.
    if (value && !await Biometric.authenticate()) return;
    await Biometric.setEnabled(value);
    if (!mounted) return;
    setState(() => _biometricEnabled = value);
  }

  Future<void> _toggleNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      if (value) {
        await ApiClient.registerDevice(token: token, clientLogin: _phone);
      } else {
        await ApiClient.unregisterDevice(token);
      }
    }
    setState(() => _notifications = value);
  }

  Future<void> _logout() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await ApiClient.unregisterDevice(token);
    // Удаляем регистрацию приложения в биллинге (cmd=del), затем чистим локально.
    final app = await AuthStore().appToken;
    if (app != null) await BillingApi.deleteApp(app);
    await AuthStore().clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Карточка аккаунта
          _card(
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: _brand,
                  child: Icon(Icons.person, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatPhone(_phone),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text('Абонент Интерры',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Уведомления'),
          _card(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Push-уведомления'),
              subtitle: const Text('Баланс, тариф, статусы заявок'),
              value: _notifications,
              activeThumbColor: _brand,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              onChanged: _toggleNotifications,
            ),
          ),
          if (_biometricAvailable) ...[
            const SizedBox(height: 18),
            _sectionTitle('Безопасность'),
            _card(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Вход по Face ID / отпечатку'),
                subtitle: const Text('Запрашивать при открытии приложения'),
                value: _biometricEnabled,
                activeThumbColor: _brand,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                onChanged: _toggleBiometric,
              ),
            ),
          ],
          const SizedBox(height: 18),
          _sectionTitle('Аккаунт'),
          _card(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.logout, color: _brand),
              title: const Text('Выйти из аккаунта',
                  style: TextStyle(color: _brand, fontWeight: FontWeight.w500)),
              onTap: _logout,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('ЛК Интерра · v0.1.0',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// Форматирует 11-значный номер вида 79229999999 → +7 922 999-99-99.
  String _formatPhone(String? phone) {
    final d = phone?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (d.length != 11) return phone ?? '—';
    return '+${d[0]} ${d.substring(1, 4)} ${d.substring(4, 7)}-'
        '${d.substring(7, 9)}-${d.substring(9)}';
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
}
