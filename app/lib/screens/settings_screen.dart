import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_store.dart';
import '../services/api_client.dart';
import 'login_screen.dart';

const Color _brand = Color(0xFFE3000F);

/// Экран настроек: аккаунт, уведомления, выход.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _login;
  bool _notifications = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final login = await AuthStore().login;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _login = login;
      _notifications = prefs.getBool('notifications_enabled') ?? true;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      if (value) {
        await ApiClient.registerDevice(token: token, clientLogin: _login);
      } else {
        await ApiClient.unregisterDevice(token);
      }
    }
    setState(() => _notifications = value);
  }

  Future<void> _logout() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await ApiClient.unregisterDevice(token);
    await AuthStore().clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        (_login != null && _login!.isNotEmpty) ? _login![0].toUpperCase() : '?';
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Карточка аккаунта
          _card(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _brand,
                  child: Text(
                    initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _login ?? '—',
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
