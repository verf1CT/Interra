import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../theme.dart';
import '../utils/phone.dart';
import '../services/auth_store.dart';
import '../services/api_client.dart';
import '../services/billing_api.dart';
import '../services/biometric.dart';
import '../services/notify_prefs.dart';
import '../services/pin_lock.dart';
import '../services/push_service.dart';
import 'pin_setup_screen.dart';
import 'register_screen.dart';
import 'support_screen.dart';

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
  bool _pinSet = false;
  final Map<String, bool> _categories = {}; // ключ категории → включена

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
    final pinSet = await PinLock.isSet;
    final cats = <String, bool>{};
    for (final c in NotifyPrefs.categories) {
      cats[c.key] = await NotifyPrefs.isEnabled(c.key);
    }
    setState(() {
      _phone = phone;
      _notifications = prefs.getBool('notifications_enabled') ?? true;
      _biometricAvailable = bioAvail;
      _biometricEnabled = bioOn;
      _pinSet = pinSet;
      _categories
        ..clear()
        ..addAll(cats);
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

  Future<void> _togglePin(bool value) async {
    if (value) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => const PinSetupScreen(),
        settings: const RouteSettings(name: 'pin_setup'),
      ));
      if (ok == true && mounted) setState(() => _pinSet = true);
    } else {
      // Отключение защищаем вводом текущего кода.
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => const PinVerifyScreen(),
        settings: const RouteSettings(name: 'pin_verify'),
      ));
      if (ok == true) {
        await PinLock.clear();
        if (mounted) setState(() => _pinSet = false);
      }
    }
  }

  Future<void> _changePin() async {
    // Смена: сначала текущий код, затем установка нового.
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => const PinVerifyScreen(),
      settings: const RouteSettings(name: 'pin_verify'),
    ));
    if (ok != true || !mounted) return;
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => const PinSetupScreen(),
      settings: const RouteSettings(name: 'pin_setup'),
    ));
  }

  Future<void> _toggleNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
    // getToken на iOS без APNs может висеть/падать — не блокируем переключатель.
    try {
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 5));
      if (token != null) {
        if (value) {
          // Регистрируем через PushService — он передаёт сегменты категорий.
          await PushService.registerCurrentToken();
        } else {
          await ApiClient.unregisterDevice(token);
        }
      }
    } catch (e) {
      debugPrint('toggleNotifications: push-токен пропущен: $e');
    }
    if (!mounted) return;
    setState(() => _notifications = value);
  }

  Future<void> _toggleCategory(String key, bool value) async {
    await NotifyPrefs.setEnabled(key, value);
    if (mounted) setState(() => _categories[key] = value);
    // Обновляем сегменты на бэкенде (best-effort, сеть может отсутствовать).
    PushService.registerCurrentToken();
  }

  Future<void> _logout() async {
    // Удаление push-токена и регистрации в биллинге — best-effort: на iOS без
    // APNs getToken/сеть могут висеть или падать, но выход должен срабатывать
    // ВСЕГДА. Поэтому удалённые операции не блокируют локальную очистку и переход.
    try {
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 5));
      if (token != null) await ApiClient.unregisterDevice(token);
    } catch (e) {
      debugPrint('logout: удаление push-токена пропущено: $e');
    }
    try {
      final app = await AuthStore().appToken;
      if (app != null) await BillingApi.deleteApp(app);
    } catch (e) {
      debugPrint('logout: удаление регистрации в биллинге пропущено: $e');
    }
    await AuthStore().clear();
    await Biometric.setEnabled(false); // снимаем биометрический замок при выходе
    await PinLock.clear(); // и код-пароль
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
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.brand, AppColors.accent],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatRuPhoneFull(_phone),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      _statusChip(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Уведомления'),
          _card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: const Text('Push-уведомления'),
                  subtitle: const Text('Баланс, тариф, статусы заявок'),
                  value: _notifications,
                  activeThumbColor: AppColors.brand,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  onChanged: _toggleNotifications,
                ),
                if (_notifications)
                  for (final c in NotifyPrefs.categories) ...[
                    const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 68,
                        color: AppColors.line),
                    SwitchListTile(
                      secondary: const SizedBox.shrink(),
                      title: Text(c.title,
                          style: const TextStyle(fontSize: 15)),
                      subtitle: Text(c.subtitle,
                          style: const TextStyle(fontSize: 12.5)),
                      value: _categories[c.key] ?? true,
                      activeThumbColor: AppColors.brand,
                      dense: true,
                      contentPadding: const EdgeInsets.only(
                          left: 16, right: 16, top: 2, bottom: 2),
                      onChanged: (v) => _toggleCategory(c.key, v),
                    ),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Безопасность'),
          _card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (_biometricAvailable)
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('Вход по Face ID / отпечатку'),
                    subtitle:
                        const Text('Не чаще, чем раз в 30 минут'),
                    value: _biometricEnabled,
                    activeThumbColor: AppColors.brand,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    onChanged: _toggleBiometric,
                  ),
                if (_biometricAvailable)
                  const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 68,
                      color: AppColors.line),
                SwitchListTile(
                  secondary: const Icon(Icons.pin_outlined),
                  title: const Text('Код-пароль'),
                  subtitle: Text(_pinSet
                      ? 'Запасной вход, если Face ID недоступен'
                      : 'Четырёхзначный код для входа'),
                  value: _pinSet,
                  activeThumbColor: AppColors.brand,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  onChanged: _togglePin,
                ),
                if (_pinSet) ...[
                  const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 68,
                      color: AppColors.line),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 0),
                    leading: const SizedBox.shrink(),
                    title: const Text('Изменить код-пароль',
                        style: TextStyle(fontSize: 15)),
                    trailing:
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                    onTap: _changePin,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Помощь'),
          _card(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.support_agent_rounded,
                  color: AppColors.brand),
              title: const Text('Поддержка'),
              subtitle: const Text('Звонок, Telegram, помощь на сайте'),
              trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SupportScreen(),
                  settings: const RouteSettings(name: 'support'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Аккаунт'),
          _card(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.logout, color: AppColors.brand),
              title: const Text('Выйти из аккаунта',
                  style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w500)),
              onTap: _logout,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('ЛК Интерра · v${AppConfig.appVersion}',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// Бейдж статуса приложения: регистрация в биллинге активна.
  Widget _statusChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.ok.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  color: AppColors.ok, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            const Text('Подключено',
                style: TextStyle(
                    color: AppColors.ok,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

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
