import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/biometric.dart';

/// Биометрический замок поверх всего приложения. Запрашивает Face ID / отпечаток
/// при холодном старте и при каждом возврате из фона, если вход по биометрии
/// включён в настройках. Размещается через `MaterialApp.builder`, поэтому
/// перекрывает в том числе вложенные экраны (настройки и т.п.).
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockIfEnabled();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Запрос Face ID сам по себе шлёт inactive (не paused), поэтому замок
    // перезахватываем только после реального ухода в фон — без зацикливания.
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    } else if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      _lockIfEnabled();
    }
  }

  Future<void> _lockIfEnabled() async {
    if (_locked) return;
    if (await Biometric.isEnabled) {
      if (!mounted) return;
      setState(() => _locked = true);
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_authInProgress) return;
    setState(() => _authInProgress = true);
    final ok = await Biometric.authenticate();
    if (!mounted) {
      _authInProgress = false;
      return;
    }
    setState(() {
      _authInProgress = false;
      if (ok) _locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: _LockView(busy: _authInProgress, onUnlock: _authenticate),
          ),
      ],
    );
  }
}

class _LockView extends StatelessWidget {
  final bool busy;
  final VoidCallback onUnlock;
  const _LockView({required this.busy, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.brand, AppColors.accent],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child:
                  const Icon(Icons.lock_outline, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 24),
            const Text('Личный кабинет заблокирован',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: busy ? null : onUnlock,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Разблокировать'),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
            ),
          ],
        ),
      ),
    );
  }
}
