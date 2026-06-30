import 'package:flutter/material.dart';
import '../theme.dart';

/// Заслонка приватности для переключателя задач.
///
/// Когда приложение уходит в фон/неактив (iOS делает снимок экрана для
/// карточки в переключателе задач, Android — для «Недавних»), поверх кабинета
/// показываем брендовую заставку. Так баланс, тариф и личные данные не попадают
/// в системный снимок и не видны посторонним, открывшим переключатель задач.
///
/// Размещается в `MaterialApp.builder` поверх [BiometricGate], поэтому
/// перекрывает в том числе экран блокировки и любые вложенные экраны.
class PrivacyShield extends StatefulWidget {
  final Widget child;
  const PrivacyShield({super.key, required this.child});

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Снимок для переключателя задач делается в момент перехода в inactive
    // (на iOS — раньше paused), поэтому заслонку поднимаем уже на inactive и
    // hidden, а снимаем только при полном возврате на передний план.
    final hide = state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
    if (hide != _obscured && mounted) {
      setState(() => _obscured = hide);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_obscured) const Positioned.fill(child: _PrivacyView()),
      ],
    );
  }
}

/// Брендовая заставка-заглушка (логотип на фирменном фоне). Без текста о балансе
/// и без личных данных — ровно то, что не жалко увидеть в снимке системы.
class _PrivacyView extends StatelessWidget {
  const _PrivacyView();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.brand, AppColors.accent],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withValues(alpha: 0.30),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.wifi_rounded, color: Colors.white, size: 48),
        ),
      ),
    );
  }
}
