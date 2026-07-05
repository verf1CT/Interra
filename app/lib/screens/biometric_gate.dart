import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/biometric.dart';
import '../services/pin_lock.dart';
import '../widgets/pin_pad.dart';

/// замок поверх всего приложения: Face ID / отпечаток и/или код-пароль.
///
/// Показывается при холодном старте и возврате из фона, если защита включена
/// и льготный период ([Biometric.gracePeriod]) истёк - чтобы не запрашивать
/// разблокировку при каждом переключении приложений.
/// Размещается через `MaterialApp.builder`, поэтому перекрывает в том числе
/// вложенные экраны (настройки и т.п.)
class BiometricGate extends StatefulWidget {
  final Widget child;
  const BiometricGate({super.key, required this.child});

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _authInProgress = false;
  bool _wasPaused = false;
  bool _bioEnabled = false;
  bool _pinSet = false;
  // последнее известное «защита включена» - чтобы на возврате из фона решить
  // синхронно, поднимать ли шторку, ещё до асинхронной проверки
  bool _protectionOn = false;
  // нейтральная шторка на те миллисекунды, пока идёт асинхронная проверка
  // замка при возврате из фона: без неё кабинет с балансом мелькает до замка
  bool _coverForCheck = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockIfNeeded();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // запрос Face ID сам по себе шлёт inactive (не paused), поэтому замок
    // перезахватываем только после реального ухода в фон - без зацикливания
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    } else if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      // мгновенно (без await) прикрываем кабинет нейтральной шторкой, если
      // защита включена и льготный период - судя по кэшу - истёк. авторитетно
      // решит асинхронный _lockIfNeeded ниже, но шторка убирает мелькание
      if (!_locked && _protectionOn && !Biometric.withinGracePeriodSync()) {
        setState(() => _coverForCheck = true);
      }
      _lockIfNeeded();
    }
  }

  Future<void> _lockIfNeeded() async {
    if (_locked) return;
    final bio = await Biometric.isEnabled;
    final pin = await PinLock.isSet;
    _protectionOn = bio || pin;
    final grace = _protectionOn ? await Biometric.withinGracePeriod : false;
    if (!mounted) return;
    if (!_protectionOn || grace) {
      // замок не нужен - снимаем синхронную шторку, если поднимали
      if (_coverForCheck) setState(() => _coverForCheck = false);
      return;
    }
    setState(() {
      _locked = true;
      _coverForCheck = false;
      _bioEnabled = bio;
      _pinSet = pin;
    });
    if (bio) _authenticateBio();
  }

  Future<void> _authenticateBio() async {
    if (_authInProgress) return;
    setState(() => _authInProgress = true);
    final ok = await Biometric.authenticate();
    if (!mounted) {
      _authInProgress = false;
      return;
    }
    if (ok) {
      await Biometric.markUnlocked();
      if (!mounted) return;
    }
    setState(() {
      _authInProgress = false;
      if (ok) _locked = false;
    });
  }

  Future<bool> _submitPin(String pin) async {
    final ok = await PinLock.verify(pin);
    if (ok) {
      await Biometric.markUnlocked();
      if (mounted) setState(() => _locked = false);
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // нейтральная шторка на время асинхронной проверки замка (без данных)
        if (_coverForCheck && !_locked)
          const Positioned.fill(child: _CheckCover()),
        if (_locked)
          Positioned.fill(
            child: _LockView(
              busy: _authInProgress,
              pinSet: _pinSet,
              bioEnabled: _bioEnabled,
              onBiometric: _authenticateBio,
              onPin: _submitPin,
            ),
          ),
      ],
    );
  }
}

/// нейтральная шторка на те миллисекунды, пока идёт асинхронная проверка замка
/// при возврате из фона. без баланса и личных данных; тот же значок замка, что
/// и на экране блокировки - переход шторка→замок получается бесшовным
class _CheckCover extends StatelessWidget {
  const _CheckCover();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.p.bg,
      child: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.lock_outline,
              color: AppColors.brand, size: 34),
        ),
      ),
    );
  }
}

class _LockView extends StatelessWidget {
  final bool busy;
  final bool pinSet;
  final bool bioEnabled;
  final VoidCallback onBiometric;
  final Future<bool> Function(String) onPin;

  const _LockView({
    required this.busy,
    required this.pinSet,
    required this.bioEnabled,
    required this.onBiometric,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.p.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline,
                      color: AppColors.brand, size: 34),
                ),
                const SizedBox(height: 24),
                if (pinSet)
                  // код-пароль установлен: цифровая клавиатура, биометрия -
                  // кнопкой в нижнем ряду (если включена)
                  PinPad(
                    title: 'Введите код-пароль',
                    onSubmit: onPin,
                    onBiometric: bioEnabled && !busy ? onBiometric : null,
                  )
                else ...[
                  const Text('Личный кабинет заблокирован',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: busy ? null : onBiometric,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Разблокировать'),
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(220, 52)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
