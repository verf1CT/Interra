import 'package:flutter/material.dart';
import '../services/biometric.dart';
import 'webview_screen.dart';

const Color _brand = Color(0xFF3C98D4);
const Color _accent = Color(0xFFF4752D);

/// Экран биометрической блокировки. Показывается при запуске (и из фона),
/// если в настройках включён вход по Face ID / отпечатку.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await Biometric.authenticate();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WebViewScreen()),
      );
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      body: Center(
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
                  colors: [_brand, _accent],
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
              onPressed: _busy ? null : _unlock,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Разблокировать'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(220, 52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
