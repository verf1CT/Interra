import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../services/balance_store.dart';
import '../theme.dart';

/// анимационные примитивы, перенесённые с web-компонентов 21st.dev
/// (motion-primitives от ibelick и magic ui) на flutter

/// пружина как в motion/react: `type: 'spring', stiffness, damping, mass`.
/// [seconds] - сколько секунд симуляции укладывается в длительность анимации
class SpringCurve extends Curve {
  final double mass;
  final double stiffness;
  final double damping;
  final double seconds;

  const SpringCurve({
    this.mass = 0.3,
    this.stiffness = 280,
    this.damping = 18,
    this.seconds = 0.6,
  });

  /// чуть пружинит в конце - для «пилюль» навигации и сегментов
  static const bouncy =
      SpringCurve(mass: 1, stiffness: 320, damping: 24, seconds: 0.55);

  /// параметры SlidingNumber из motion-primitives - почти без перелёта
  static const digits =
      SpringCurve(mass: 0.3, stiffness: 280, damping: 18, seconds: 0.7);

  @override
  double transformInternal(double t) {
    final sim = SpringSimulation(
      SpringDescription(mass: mass, stiffness: stiffness, damping: damping),
      0,
      1,
      0,
    );
    return sim.x(t * seconds);
  }
}

/// SlidingNumber (motion-primitives): каждая цифра - вертикальная лента 0-9,
/// которая на пружине доезжает до нового значения. формат суммы тот же,
/// что у баланса во всём приложении (BalanceStore.format)
class SlidingNumber extends StatelessWidget {
  final double value;
  final TextStyle style;

  const SlidingNumber({super.key, required this.value, required this.style});

  @override
  Widget build(BuildContext context) {
    final text = BalanceStore.format(value);
    final effective = DefaultTextStyle.of(context).style.merge(style).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final chars = text.split('');
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chars.length; i++)
            if (RegExp(r'\d').hasMatch(chars[i]))
              // ключ - позиция с конца строки: разряды не «перескакивают»,
              // когда меняется количество цифр
              _RollingDigit(
                key: ValueKey('d${chars.length - i}'),
                digit: int.parse(chars[i]),
                style: effective,
              )
            else
              Text(chars[i], style: effective),
        ],
      ),
    );
  }
}

class _RollingDigit extends StatelessWidget {
  final int digit;
  final TextStyle style;

  const _RollingDigit({super.key, required this.digit, required this.style});

  @override
  Widget build(BuildContext context) {
    final tp = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final h = tp.height;
    final w = tp.width;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: digit.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: SpringCurve.digits,
      builder: (context, v, _) {
        return SizedBox(
          width: w,
          height: h,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (var n = 0; n < 10; n++)
                  Transform.translate(
                    offset: Offset(0, _offset(n, v) * h),
                    child: Text('$n', style: style),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// та же формула, что в motion-primitives: ближайший путь по кругу 0-9
  static double _offset(int n, double v) {
    final place = v % 10;
    var o = (10 + n - place) % 10;
    if (o > 5) o -= 10;
    return o;
  }
}

/// нажатие с лёгким «вдавливанием» и тактильным откликом
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final String? semanticLabel;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.semanticLabel,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Duration(milliseconds: _down ? 90 : 260),
          curve: _down ? Curves.easeOut : SpringCurve.bouncy,
          child: widget.child,
        ),
      ),
    );
  }
}

/// AnimatedBackground (motion-primitives) в виде сегментов: подложка
/// активного пункта переезжает между вариантами. [position] - дробный
/// индекс, поэтому подложка может идти за пальцем при свайпе TabBarView
class SlidingSegmented extends StatelessWidget {
  final List<String> labels;
  final double position;
  final ValueChanged<int> onChanged;

  const SlidingSegmented({
    super.key,
    required this.labels,
    required this.position,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final segW = c.maxWidth / labels.length;
        return Stack(
          children: [
            Positioned(
              left: position * segW,
              top: 0,
              bottom: 0,
              width: segW,
              child: Container(
                decoration: BoxDecoration(
                  color: dark ? p.line : p.card,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: dark
                      ? null
                      : const [
                          BoxShadow(
                              color: Color(0x141B2733),
                              blurRadius: 6,
                              offset: Offset(0, 2)),
                        ],
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onChanged(i);
                      },
                      child: Center(
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontFamily: kFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color.lerp(
                              p.ink,
                              p.inkMute,
                              (position - i).abs().clamp(0.0, 1.0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// BorderBeam (magic ui): по контуру карточки бежит короткий блик.
/// включаем только когда идёт обновление данных - это индикатор, а не декор
class BorderBeam extends StatefulWidget {
  final Widget child;
  final bool active;
  final double radius;
  final Color color;
  final double width;

  const BorderBeam({
    super.key,
    required this.child,
    required this.active,
    this.radius = 24,
    this.color = Colors.white,
    this.width = 1.6,
  });

  @override
  State<BorderBeam> createState() => _BorderBeamState();
}

class _BorderBeamState extends State<BorderBeam>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(BorderBeam old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _BeamPainter(
        progress: _c,
        visible: widget.active,
        radius: widget.radius,
        color: widget.color,
        width: widget.width,
      ),
      child: widget.child,
    );
  }
}

class _BeamPainter extends CustomPainter {
  final Animation<double> progress;
  final bool visible;
  final double radius;
  final Color color;
  final double width;

  _BeamPainter({
    required this.progress,
    required this.visible,
    required this.radius,
    required this.color,
    required this.width,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
        rect.deflate(width / 2), Radius.circular(radius - width / 2));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0),
          color,
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.72, 0.9, 1],
        transform: GradientRotation(progress.value * 2 * math.pi),
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_BeamPainter old) =>
      old.visible != visible || old.color != color || old.radius != radius;
}

/// плашка-заглушка, пока грузятся второстепенные данные
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// появление блоков снизу с небольшой задержкой по очереди
class StaggerIn extends StatelessWidget {
  final int index;
  final Widget child;

  const StaggerIn({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final delay = (index * 0.08).clamp(0.0, 0.5);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 520 + (delay * 1000).round()),
      curve: Interval(delay, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: child,
    );
  }
}
