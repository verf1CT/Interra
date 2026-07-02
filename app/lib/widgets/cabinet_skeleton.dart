import 'package:flutter/material.dart';
import '../theme.dart';

/// скелетон-заглушка кабинета на время загрузки: серые «плашки» баланса,
/// тарифа и списка с мягким шиммером - ощущение скорости вместо спиннера
class CabinetSkeleton extends StatefulWidget {
  const CabinetSkeleton({super.key});

  @override
  State<CabinetSkeleton> createState() => _CabinetSkeletonState();
}

class _CabinetSkeletonState extends State<CabinetSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.all(16),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Color(0xFFE4E7EB),
                  Color(0xFFF3F5F7),
                  Color(0xFFE4E7EB),
                ],
                stops: const [0.25, 0.5, 0.75],
                transform: _SlidingGradient(_c.value * 2 - 1),
              ).createShader(rect);
            },
            child: child,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _box(height: 110, radius: 18), // карточка баланса
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _box(height: 72, radius: 16)),
                const SizedBox(width: 14),
                Expanded(child: _box(height: 72, radius: 16)),
              ],
            ),
            const SizedBox(height: 24),
            _box(height: 16, width: 140, radius: 6), // заголовок раздела
            const SizedBox(height: 16),
            for (var i = 0; i < 5; i++) ...[
              _box(height: 48, radius: 12),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _box({required double height, double? width, double radius = 12}) =>
      Container(
        height: height,
        width: width ?? double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFE4E7EB),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// сдвигает градиент по горизонтали для эффекта бегущего блика
class _SlidingGradient extends GradientTransform {
  final double slide; // -1..1
  const _SlidingGradient(this.slide);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * slide, 0, 0);
}
