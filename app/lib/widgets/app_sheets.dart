import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

/// общая оболочка нижних шторок: ручка, скругление сверху, тонкая рамка
class _SheetShell extends StatelessWidget {
  final Widget child;
  const _SheetShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: context.p.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.p.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> _showSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) => _SheetShell(child: child),
  );
}

/// подтверждение действия шторкой снизу вместо AlertDialog.
/// возвращает true, если пользователь подтвердил
Future<bool> showConfirmSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Отмена',
  bool danger = true,
}) async {
  final accent = danger ? AppColors.danger : AppColors.brand;
  final res = await _showSheet<bool>(
    context,
    Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 26),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: ctx.p.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.4,
              color: ctx.p.inkMute,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(ctx).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: Text(confirmLabel),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: ctx.p.inkMute,
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              child: Text(cancelLabel),
            ),
          ),
        ],
      ),
    ),
  );
  return res == true;
}

/// выбор одного варианта шторкой снизу вместо SimpleDialog
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) {
  return _showSheet<T>(
    context,
    Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: ctx.p.ink,
            ),
          ),
          const SizedBox(height: 14),
          for (final o in options) ...[
            _ChoiceRow(
              label: o.$2,
              selected: o.$1 == selected,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(ctx).pop(o.$1);
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}

class _ChoiceRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceRow({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brand.withValues(alpha: 0.08) : context.p.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.brand : context.p.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: context.p.ink,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: AppColors.brand, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
