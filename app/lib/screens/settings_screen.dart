import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_store.dart';
import '../services/api_client.dart';
import 'login_screen.dart';

/// Экран настроек: показывает текущий логин, переключатель уведомлений,
/// порог низкого баланса и выход из аккаунта.
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        backgroundColor: const Color(0xFFE3000F),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Логин'),
            subtitle: Text(_login ?? '—'),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.notifications),
            title: const Text('Push-уведомления'),
            subtitle: const Text('Баланс, тариф, статусы заявок'),
            value: _notifications,
            activeThumbColor: const Color(0xFFE3000F),
            onChanged: _toggleNotifications,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Выйти из аккаунта',
                style: TextStyle(color: Colors.red)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}
