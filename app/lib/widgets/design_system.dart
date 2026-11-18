import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lk_interra/theme.dart';
import 'package:lk_interra/services/balance_store.dart';

/// 1. PulseDot: Живой пульсирующий светодиод статуса соединения (21st.dev style).
/// Непрерывная плавная волна светового кольца позади точки статуса.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final String label;

  const PulseDot({
    super.key,
    required this.color,
    this.size = 8.0,
    required this.label,
  });

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.color.withValues(alpha: 0.20),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size * 2,
            height: widget.size * 2,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final progress = _controller.value;
                    return Container(
                      width: widget.size + (widget.size * progress * 1.4),
                      height: widget.size + (widget.size * progress * 1.4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.color.withValues(alpha: (1.0 - progress) * 0.4),
                      ),
                    );
                  },
                ),
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.6),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: widget.color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 2. NumberTicker: Плавная накрутка цифр баланса при загрузке/обновлении (Magic UI / 21st.dev).
class NumberTicker extends StatelessWidget {
  final double value;
  final TextStyle? style;
  final Duration duration;

  const NumberTicker({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 700),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, val, _) {
        final formatted = BalanceStore.format(val);
        return Text(
          formatted,
          style: (style ?? TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: context.p.ink,
          )).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}

/// 3. MorphingCopyBadge: Интерактивная плашка копирования с морфингом иконки в галочку
class MorphingCopyBadge extends StatefulWidget {
  final String textToCopy;
  final String displayLabel;

  const MorphingCopyBadge({
    super.key,
    required this.textToCopy,
    required this.displayLabel,
  });

  @override
  State<MorphingCopyBadge> createState() => _MorphingCopyBadgeState();
}

class _MorphingCopyBadgeState extends State<MorphingCopyBadge> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.textToCopy));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = _copied
        ? const Color(0xFF10B981).withValues(alpha: 0.12)
        : (dark ? const Color(0xFF232E39) : const Color(0xFFEEF2F6));
    final borderColor = _copied
        ? const Color(0xFF10B981).withValues(alpha: 0.3)
        : context.p.line;

    return InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.displayLabel,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: context.p.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: _copied
                  ? const Row(
                      key: ValueKey('copied'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, size: 14, color: Color(0xFF10B981)),
                        SizedBox(width: 3),
                        Text(
                          'скопирован',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    )
                  : Icon(
                      Icons.copy_rounded,
                      key: const ValueKey('copy_icon'),
                      size: 13,
                      color: context.p.inkMute,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
