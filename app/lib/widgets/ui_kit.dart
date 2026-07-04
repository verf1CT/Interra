import 'package:flutter/material.dart';
import '../theme.dart';

/// общие элементы интерфейса, чтобы стиль был в одном месте (после редизайна
/// одинаковые карточки/заголовки/значки были скопированы по экранам)

/// карточка со светлой заливкой - единая обёртка
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool clip; // обрезать содержимое по скруглению (для списков с разделителями)

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 12,
    this.clip = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        clipBehavior: clip ? Clip.antiAlias : Clip.none,
        decoration: cardBox(context, radius: radius),
        child: child,
      );
}

/// заголовок раздела: КАПС, приглушённый серый
class AppSectionTitle extends StatelessWidget {
  final String text;
  const AppSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.p.inkFaint,
            letterSpacing: 0.5,
          ),
        ),
      );
}

/// цветной значок-подложка для ListTile.leading
class IconChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconChip(this.icon, this.color, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: size * 0.55),
      );
}
