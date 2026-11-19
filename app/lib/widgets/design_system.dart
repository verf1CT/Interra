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

/// 4. ModernBottomNav: Чистый нативный подвал приложения в стиле Yota / современных телекомов.
/// Все вкладки всегда подписаны (иконка сверху, подпись снизу). Активная вкладка акцентирована фирменным цветом.
class ModernNavItem {
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;

  const ModernNavItem({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
  });
}

class ModernBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<ModernNavItem> items;

  const ModernBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.p.card,
        border: Border(
          top: BorderSide(
            color: context.p.line,
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (index) {
              final isSelected = index == currentIndex;
              final item = items[index];
              return Expanded(
                child: _buildItem(context, item, isSelected, () => onTap(index)),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    ModernNavItem item,
    bool isSelected,
    VoidCallback onSelect,
  ) {
    final activeColor = AppColors.brand;
    final inactiveColor = context.p.inkMute;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onSelect();
      },
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Icon(
                isSelected ? item.activeIcon : item.inactiveIcon,
                size: 24,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontFamily: kFont,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
                height: 1.1,
              ),
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 5. ExpandingBottomNav: Плавающий анимированный бар навигации (21st.dev @arunachalam style).
/// Пин-капсула над нижним краем, где активный таб плавно раскрывается с иконкой и подписью,
/// а неактивные пункты сжаты до минималистичных контурных иконок.
class ExpandingNavItem {
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;

  const ExpandingNavItem({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
  });
}

class ExpandingBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<ExpandingNavItem> items;

  const ExpandingBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 4),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: context.p.card.withValues(alpha: isDark ? 0.94 : 0.97),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: context.p.line, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(items.length, (index) {
              final isSelected = index == currentIndex;
              final item = items[index];
              return _buildTabItem(context, item, isSelected, () => onTap(index));
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(
    BuildContext context,
    ExpandingNavItem item,
    bool isSelected,
    VoidCallback onSelect,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onSelect();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 14 : 10,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brand.withValues(alpha: isDark ? 0.20 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? item.activeIcon : item.inactiveIcon,
              size: 20,
              color: isSelected ? AppColors.brand : context.p.inkMute,
            ),
            AnimatedCrossFade(
              firstChild: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                    height: 1.1,
                  ),
                ),
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState:
                  isSelected ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 220),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

/// 6. 21st.dev Style Pill Components for Settings & Screens

class PillSectionHeader extends StatelessWidget {
  final String title;
  const PillSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: kFont,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.08,
          color: context.p.inkFaint,
        ),
      ),
    );
  }
}

class PillGroupCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  const PillGroupCard({
    super.key,
    required this.children,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.p.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.p.line,
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class PillTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const PillTile({
    super.key,
    required this.icon,
    this.iconColor = AppColors.brand,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: iconColor.withValues(alpha: 0.08),
        highlightColor: iconColor.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: kFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.p.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: kFont,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                          color: context.p.inkMute,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PillDivider extends StatelessWidget {
  const PillDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.8,
      indent: 64,
      endIndent: 14,
      color: context.p.line,
    );
  }
}

class PillChip extends StatelessWidget {
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const PillChip({
    super.key,
    required this.label,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.p.inkMute;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: effectiveColor.withValues(alpha: 0.20),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: kFont,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: effectiveColor,
          ),
        ),
      ),
    );
  }
}
