import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/pin_lock.dart';

/// цифровая клавиатура с точками ввода PIN.
///
/// [onSubmit] вызывается при наборе [PinLock.length] цифр; вернуть false -
/// ввод неверный: точки встряхиваются и очищаются. [onBiometric] - необязательная
/// кнопка Face ID / отпечатка в нижнем ряду
class PinPad extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Future<bool> Function(String pin) onSubmit;
  final VoidCallback? onBiometric;

  const PinPad({
    super.key,
    required this.title,
    this.subtitle,
    required this.onSubmit,
    this.onBiometric,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _entered = '';
  bool _busy = false;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _tap(String digit) async {
    if (_busy || _entered.length >= PinLock.length) return;
    HapticFeedback.selectionClick();
    setState(() => _entered += digit);
    if (_entered.length < PinLock.length) return;

    setState(() => _busy = true);
    final ok = await widget.onSubmit(_entered);
    if (!mounted) return;
    if (ok) return; // экран сверху закроют/разблокируют - сбрасывать нечего
    HapticFeedback.vibrate();
    await _shake.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _entered = '';
      _busy = false;
    });
  }

  void _backspace() {
    if (_busy || _entered.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 6),
          Text(widget.subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.inkMute)),
        ],
        const SizedBox(height: 22),
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            // затухающее знакопеременное смещение - «неверный код»
            final t = _shake.value;
            final dx = (1 - t) * 10 * (t * 40).truncate().isEven.toSign();
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: _dots(),
        ),
        const SizedBox(height: 30),
        _keys(),
      ],
    );
  }

  Widget _dots() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < PinLock.length; i++)
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _entered.length
                    ? AppColors.brand
                    : Colors.transparent,
                border: Border.all(
                  color: i < _entered.length
                      ? AppColors.brand
                      : AppColors.inkFaint,
                  width: 1.6,
                ),
              ),
            ),
        ],
      );

  Widget _keys() {
    Widget key(String d) => _key(
          child: Text(d,
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.w500)),
          onTap: () => _tap(d),
        );

    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final d in row) key(d)],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.onBiometric != null
                ? _key(
                    child: const Icon(Icons.fingerprint,
                        size: 30, color: AppColors.brand),
                    onTap: widget.onBiometric!,
                  )
                : _keySpacer(),
            key('0'),
            _key(
              child: Icon(Icons.backspace_outlined,
                  size: 24, color: AppColors.inkMute),
              onTap: _backspace,
            ),
          ],
        ),
      ],
    );
  }

  Widget _key({required Widget child, required VoidCallback onTap}) => Padding(
        padding: const EdgeInsets.all(7),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.card,
              boxShadow: [
                BoxShadow(
                    color: Color(0x141B2733),
                    blurRadius: 10,
                    offset: Offset(0, 3)),
              ],
            ),
            child: child,
          ),
        ),
      );

  Widget _keySpacer() =>
      const Padding(padding: EdgeInsets.all(7), child: SizedBox(width: 72, height: 72));
}

extension on bool {
  double toSign() => this ? 1.0 : -1.0;
}
