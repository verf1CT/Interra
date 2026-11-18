import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

/// заслонка приватности для переключателя задач.
///
/// Когда приложение уходит в фон/неактив (iOS делает снимок экрана для
/// карточки в переключателе задач, Android - для «Недавних»), поверх кабинета
/// показываем брендовую заставку. так баланс, тариф и личные данные не попадают
/// в системный снимок и не видны посторонним, открывшим переключатель задач.
///
/// Размещается в `MaterialApp.builder` поверх [BiometricGate], поэтому
/// перекрывает в том числе экран блокировки и любые вложенные экраны
class PrivacyShield extends StatefulWidget {
  final Widget child;
  const PrivacyShield({super.key, required this.child});

  static final ValueNotifier<bool> isEnabled = ValueNotifier<bool>(true);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabled.value = prefs.getBool('privacy_shield_enabled') ?? true;
    } catch (_) {}
  }

  static Future<void> setEnabled(bool value) async {
    isEnabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('privacy_shield_enabled', value);
    } catch (_) {}
  }

  @override
  State<PrivacyShield> createState() => _PrivacyShieldState();
}

class _PrivacyShieldState extends State<PrivacyShield>
    with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PrivacyShield.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!PrivacyShield.isEnabled.value) {
      if (_obscured && mounted) {
        setState(() => _obscured = false);
      }
      return;
    }

    // снимок для переключателя задач делается в момент перехода в inactive
    // (на iOS - раньше paused), поэтому заслонку поднимаем уже на inactive и
    // hidden, а снимаем только при полном возврате на передний план
    final hide = state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
    if (hide != _obscured && mounted) {
      setState(() => _obscured = hide);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PrivacyShield.isEnabled,
      builder: (context, enabled, _) {
        return Stack(
          children: [
            widget.child,
            if (_obscured && enabled)
              const Positioned.fill(child: _PrivacyView()),
          ],
        );
      },
    );
  }
}

/// брендовая заставка-заглушка (логотип на фирменном фоне). без текста о балансе
/// и без личных данных - ровно то, что не жалко увидеть в снимке системы
class _PrivacyView extends StatelessWidget {
  const _PrivacyView();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.p.bg,
      child: Center(
        child: Container(
          width: 92,
          height: 92,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Image.asset('assets/splash_logo.png', fit: BoxFit.cover),
        ),
      ),
    );
  }
}
