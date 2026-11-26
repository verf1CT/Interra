import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../utils/phone.dart';
import '../services/app_info.dart';
import '../services/auth_store.dart';
import '../services/cabinet_parser.dart';
import '../services/demo_mode.dart';
import '../services/api_client.dart';
import '../services/balance_store.dart';
import '../services/billing_api.dart';
import '../services/biometric.dart';
import '../services/page_cache.dart';
import '../services/notify_prefs.dart';
import '../services/pin_lock.dart';
import '../services/push_service.dart';
import '../services/update_check.dart';
import '../widgets/privacy_shield.dart';
import '../widgets/design_system.dart';
import '../widgets/app_sheets.dart';
import 'pin_setup_screen.dart';
import 'register_screen.dart';
import 'support_screen.dart';

/// экран настроек: аккаунт, уведомления, выход
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _phone;
  bool _notifications = true;
  bool _smsNotifications = true;
  int _linkedAppsCount = 9;
  bool _unlinkingApps = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _pinSet = false;
  int _lockDelayMs = Biometric.defaultLockDelayMs;
  bool _privacyShieldEnabled = true;
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
    final lockDelay = await Biometric.lockDelayMs;
    final cats = <String, bool>{};
    for (final c in NotifyPrefs.categories) {
      cats[c.key] = await NotifyPrefs.isEnabled(c.key);
    }
    setState(() {
      _phone = phone ?? (DemoMode.isEnabled.value ? '79991234567' : null);
      _notifications = prefs.getBool('notifications_enabled') ?? true;
      _smsNotifications = prefs.getBool('sms_notifications_enabled') ?? true;
      _linkedAppsCount = prefs.getInt('linked_apps_count') ?? 9;
      _biometricAvailable = bioAvail;
      _biometricEnabled = bioOn;
      _pinSet = pinSet;
      _lockDelayMs = lockDelay;
      _privacyShieldEnabled = PrivacyShield.isEnabled.value;
      _categories
        ..clear()
        ..addAll(cats);
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    // и включение, и отключение защищаем проверкой - чтобы посторонний не
    // поставил замок чужим лицом/пальцем и, что важнее, не СНЯЛ уже
    // включённый замок, пока телефон разблокирован в руках (паритет с PIN)
    if (!await Biometric.authenticate()) return;
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
      // отключение защищаем вводом текущего кода
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

  /// выбор оформления (Авто/Светлая/Тёмная)
  Future<void> _pickTheme() async {
    final picked = await showChoiceSheet<ThemeMode>(
      context,
      title: 'Тема',
      options: [for (final m in ThemeMode.values) (m, ThemeController.label(m))],
      selected: ThemeController.mode.value,
    );
    if (picked == null) return;
    await ThemeController.set(picked);
  }

  /// выбор задержки автоблокировки - простой диалог с вариантами
  Future<void> _pickLockDelay() async {
    final picked = await showChoiceSheet<int>(
      context,
      title: 'Запрашивать вход',
      options: [for (final o in Biometric.lockDelayOptions) (o.$1, o.$2)],
      selected: _lockDelayMs,
    );
    if (picked == null) return;
    await Biometric.setLockDelayMs(picked);
    if (mounted) setState(() => _lockDelayMs = picked);
  }

  Future<void> _changePin() async {
    // смена: сначала текущий код, затем установка нового
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
    // переключатель должен реагировать мгновенно - как категории ниже.
    // сначала обновляем UI и локальную настройку, а работу с push-токеном
    // (getToken на iOS без APNs может висеть до таймаута) делаем в фоне,
    // не блокируя переключатель.
    setState(() => _notifications = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
    _syncPushRegistration(value);
  }

  /// регистрация/снятие push-токена в фоне (best-effort, сеть может отсутствовать)
  Future<void> _syncPushRegistration(bool value) async {
    try {
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 5));
      if (token != null) {
        if (value) {
          // регистрируем через PushService - он передаёт сегменты категорий
          await PushService.registerCurrentToken();
        } else {
          await ApiClient.unregisterDevice(token);
        }
      }
    } catch (e) {
      debugPrint('toggleNotifications: push-токен пропущен: $e');
    }
  }

  Future<void> _toggleCategory(String key, bool value) async {
    await NotifyPrefs.setEnabled(key, value);
    if (mounted) setState(() => _categories[key] = value);
    // обновляем сегменты на бэкенде (best-effort, сеть может отсутствовать)
    PushService.registerCurrentToken();
  }

  Future<void> _toggleSmsNotifications(bool value) async {
    setState(() => _smsNotifications = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sms_notifications_enabled', value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value
            ? 'SMS-уведомления за сутки до блокировки включены'
            : 'SMS-уведомления отключены'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmUnlinkApps() async {
    final confirmed = await showConfirmSheet(
      context,
      icon: Icons.link_off_rounded,
      title: 'Отвязать все приложения?',
      message:
          'Это завершит авторизованные сессии на всех остальных устройствах. Текущее приложение останется активным.',
      confirmLabel: 'Отвязать все',
    );

    if (!confirmed || !mounted) return;

    setState(() => _unlinkingApps = true);

    try {
      final token = await AuthStore().appToken;
      if (token != null && !DemoMode.isEnabled.value) {
        await CabinetParser.unlinkAllApps(token);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('linked_apps_count', 1);

      if (mounted) {
        setState(() {
          _linkedAppsCount = 1;
          _unlinkingApps = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Все сторонние приложения успешно отвязаны'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _unlinkingApps = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось отвязать приложения. Попробуйте позже.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showConfirmSheet(
      context,
      icon: Icons.logout_rounded,
      title: 'Выйти из аккаунта?',
      message:
          'Для повторного входа потребуется получить SMS-код на привязанный номер телефона.',
      confirmLabel: 'Выйти',
    );
    if (confirmed) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    // удаление push-токена и регистрации в биллинге - best-effort: на iOS без
    // APNs getToken/сеть могут висеть или падать, но выход должен срабатывать
    // ВСЕГДА. поэтому удалённые операции не блокируют локальную очистку и переход
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
    CabinetParser.resetSession();
    await Biometric.setEnabled(false); // снимаем биометрический замок при выходе
    await PinLock.clear(); // и код-пароль
    // персональные данные не должны переживать выход: снимок кабинета
    // (ФИО, адрес, баланс) и баланс в приложении/виджете
    await PageCache.clear();
    await BalanceStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.p.bg,
      appBar: AppBar(
        title: const Text(
          'Настройки',
          style: TextStyle(fontFamily: kFont, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          // 1. Плашка доступного обновления
          ValueListenableBuilder<String?>(
            valueListenable: UpdateCheck.available,
            builder: (context, latest, _) {
              if (latest == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.30),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        color: AppColors.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Доступна новая версия $latest - обновите приложение при следующей установке.',
                        style: TextStyle(
                          fontFamily: kFont,
                          fontSize: 13,
                          height: 1.35,
                          color: context.p.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // 2. аккаунт: номер, с которого вошли, и число привязанных устройств
          PillGroupCard(
            children: [
              PillTile(
                icon: Icons.phone_iphone_rounded,
                iconColor: context.p.ink,
                title: formatRuPhoneFull(_phone),
                subtitle: 'Номер для входа',
                trailing: PillChip(
                  label: '$_linkedAppsCount устр.',
                  color: context.p.inkMute,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const PillSectionHeader('Оформление'),
          PillGroupCard(
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeController.mode,
                builder: (context, mode, _) => PillTile(
                  icon: Icons.palette_outlined,
                  iconColor: AppColors.brand,
                  title: 'Тема оформления',
                  subtitle: 'Внешний вид интерфейса',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PillChip(
                        label: ThemeController.label(mode),
                        color: AppColors.brand,
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded, size: 20, color: context.p.inkFaint),
                    ],
                  ),
                  onTap: _pickTheme,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const PillSectionHeader('Уведомления'),
          PillGroupCard(
            children: [
              PillTile(
                icon: Icons.notifications_active_outlined,
                iconColor: AppColors.brand,
                title: 'Push-уведомления',
                subtitle: 'Баланс, тариф, важные события',
                trailing: Switch.adaptive(
                  value: _notifications,
                  activeTrackColor: AppColors.brand,
                  onChanged: _toggleNotifications,
                ),
              ),
              if (_notifications) ...[
                const PillDivider(),
                for (int i = 0; i < NotifyPrefs.categories.length; i++) ...[
                  if (i > 0) const PillDivider(),
                  () {
                    final c = NotifyPrefs.categories[i];
                    return PillTile(
                      icon: switch (c.key) {
                        'outage' => Icons.construction_rounded,
                        'balance' => Icons.account_balance_wallet_outlined,
                        'news' => Icons.campaign_outlined,
                        _ => Icons.notifications_none_rounded,
                      },
                      iconColor: AppColors.brand,
                      title: c.title,
                      subtitle: c.subtitle,
                      trailing: Switch.adaptive(
                        value: _categories[c.key] ?? true,
                        activeTrackColor: AppColors.brand,
                        onChanged: (v) => _toggleCategory(c.key, v),
                      ),
                    );
                  }(),
                ],
              ],
            ],
          ),

          const SizedBox(height: 18),
          const PillSectionHeader('Связь и устройства'),
          PillGroupCard(
            children: [
              PillTile(
                icon: Icons.sms_outlined,
                iconColor: AppColors.accent,
                title: 'SMS за сутки до блокировки',
                subtitle: 'Оповещение при низком остатке с 11 до 21 ч.',
                trailing: Switch.adaptive(
                  value: _smsNotifications,
                  activeTrackColor: AppColors.brand,
                  onChanged: _toggleSmsNotifications,
                ),
              ),
              const PillDivider(),
              PillTile(
                icon: Icons.devices_rounded,
                iconColor: AppColors.neutral,
                title: 'Активные сессии',
                subtitle: 'Привязано приложений: $_linkedAppsCount',
                trailing: OutlinedButton(
                  onPressed: _unlinkingApps ? null : _confirmUnlinkApps,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger, width: 0.8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  child: _unlinkingApps
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger),
                        )
                      : const Text(
                          'Отвязать все',
                          style: TextStyle(
                            fontFamily: kFont,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const PillSectionHeader('Безопасность и блокировка'),
          PillGroupCard(
            children: [
              if (_biometricAvailable) ...[
                PillTile(
                  icon: Icons.fingerprint_rounded,
                  iconColor: AppColors.ok,
                  title: 'Вход по Face ID / отпечатку',
                  subtitle: 'Биометрическая защита приложения',
                  trailing: Switch.adaptive(
                    value: _biometricEnabled,
                    activeTrackColor: AppColors.brand,
                    onChanged: _toggleBiometric,
                  ),
                ),
                const PillDivider(),
              ],
              PillTile(
                icon: Icons.lock_outline_rounded,
                iconColor: AppColors.brand,
                title: 'Код-пароль',
                subtitle: _pinSet
                    ? 'Запасной 4-значный код включен'
                    : 'Задать четырёхзначный код для входа',
                trailing: Switch.adaptive(
                  value: _pinSet,
                  activeTrackColor: AppColors.brand,
                  onChanged: _togglePin,
                ),
              ),
              if (_pinSet) ...[
                const PillDivider(),
                PillTile(
                  icon: Icons.password_rounded,
                  iconColor: AppColors.neutral,
                  title: 'Изменить код-пароль',
                  subtitle: 'Установить новую комбинацию',
                  trailing: Icon(Icons.chevron_right_rounded, size: 20, color: context.p.inkFaint),
                  onTap: _changePin,
                ),
              ],
              if (_biometricEnabled || _pinSet) ...[
                const PillDivider(),
                PillTile(
                  icon: Icons.timer_outlined,
                  iconColor: AppColors.neutral,
                  title: 'Запрашивать вход',
                  subtitle: 'Автоматическая блокировка экрана',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PillChip(
                        label: Biometric.lockDelayLabel(_lockDelayMs),
                        color: AppColors.brand,
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.chevron_right_rounded, size: 20, color: context.p.inkFaint),
                    ],
                  ),
                  onTap: _pickLockDelay,
                ),
              ],
              const PillDivider(),
              PillTile(
                icon: Icons.security_rounded,
                iconColor: AppColors.neutral,
                title: 'Privacy Shield',
                subtitle: 'Скрывать экран в диспетчере задач',
                trailing: Switch.adaptive(
                  value: _privacyShieldEnabled,
                  activeTrackColor: AppColors.brand,
                  onChanged: (v) async {
                    await PrivacyShield.setEnabled(v);
                    if (mounted) setState(() => _privacyShieldEnabled = v);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const PillSectionHeader('Поддержка и связь'),
          PillGroupCard(
            children: [
              PillTile(
                icon: Icons.headset_mic_rounded,
                iconColor: AppColors.brand,
                title: 'Служба заботы',
                subtitle: 'Звонок оператору, ВКонтакте, сайт',
                trailing: Icon(Icons.chevron_right_rounded, size: 20, color: context.p.inkFaint),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SupportScreen(),
                    settings: const RouteSettings(name: 'support'),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const PillSectionHeader('Сессия'),
          PillGroupCard(
            children: [
              PillTile(
                icon: Icons.logout_rounded,
                iconColor: AppColors.danger,
                title: 'Выйти из аккаунта',
                subtitle: 'Завершить авторизацию на этом устройстве',
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.danger),
                onTap: _confirmLogout,
              ),
            ],
          ),

          const SizedBox(height: 24),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: context.p.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.p.line, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brand.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ЛК Интерра · v${AppInfo.version}',
                    style: TextStyle(
                      fontFamily: kFont,
                      color: context.p.inkFaint,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

