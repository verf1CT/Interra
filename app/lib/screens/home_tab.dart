import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/auth_store.dart';
import '../services/balance_store.dart';
import '../services/cabinet_parser.dart';
import '../services/demo_mode.dart';
import '../theme.dart';
import '../utils/billing_math.dart';
import '../widgets/design_system.dart';
import '../widgets/motion_kit.dart';
import 'diagnostics_screen.dart';
import 'lan_devices_screen.dart';
import 'support_screen.dart';

/// главная вкладка кабинета. показывает только то, что реально пришло из
/// биллинга: баланс, статус, тариф, абонплату по услугам и последний платёж
class HomeTab extends StatefulWidget {
  final CabinetData data;
  final bool refreshing;
  final Future<void> Function() onRefresh;
  final VoidCallback onPay;
  final VoidCallback onPickAccount;
  final VoidCallback onOpenPassport;
  final ValueChanged<int> onOpenTab;

  const HomeTab({
    super.key,
    required this.data,
    required this.refreshing,
    required this.onRefresh,
    required this.onPay,
    required this.onPickAccount,
    required this.onOpenPassport,
    required this.onOpenTab,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _extrasLoading = true;
  double? _fee;
  PaymentItem? _lastTopUp;

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  @override
  void didUpdateWidget(HomeTab old) {
    super.didUpdateWidget(old);
    // сменился договор - абонплата и платежи у него свои
    if (old.data.account != widget.data.account) _loadExtras();
  }

  /// абонплата и последний платёж - второстепенные данные: грузим после
  /// основного экрана, при ошибке просто не показываем плитки
  Future<void> _loadExtras() async {
    setState(() => _extrasLoading = true);
    List<ServiceItem> services = const [];
    List<PaymentItem> payments = const [];
    if (DemoMode.isEnabled.value) {
      services = DemoMode.demoServices;
      payments = DemoMode.demoPayments;
    } else {
      final token = await AuthStore().appToken;
      if (token != null) {
        final r = await Future.wait([
          CabinetParser.fetchServices(token)
              .then<Object>((v) => v)
              .catchError((Object _) => const <ServiceItem>[]),
          CabinetParser.fetchPayments(token)
              .then<Object>((v) => v)
              .catchError((Object _) => const <PaymentItem>[]),
        ]);
        services = r[0] as List<ServiceItem>;
        payments = r[1] as List<PaymentItem>;
      }
    }
    if (!mounted) return;
    setState(() {
      _fee = monthlyFee(services);
      _lastTopUp = lastTopUp(payments);
      _extrasLoading = false;
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([widget.onRefresh(), _loadExtras()]);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final showStats = _extrasLoading || _fee != null || _lastTopUp != null;
    var i = 0;

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          StaggerIn(index: i++, child: _BalanceHero(
            data: d,
            refreshing: widget.refreshing,
            onPay: widget.onPay,
            onPickAccount: widget.onPickAccount,
            onHistory: () => widget.onOpenTab(3),
          )),
          if (!DemoMode.isEnabled.value && d.needsPassportData) ...[
            const SizedBox(height: 12),
            StaggerIn(index: i++, child: _Notice(
              icon: Icons.assignment_ind_outlined,
              text: 'Для договора нужны паспортные данные',
              action: 'Заполнить',
              onTap: widget.onOpenPassport,
            )),
          ],
          if (showStats) ...[
            const SizedBox(height: 12),
            StaggerIn(index: i++, child: _statsRow()),
          ],
          const SizedBox(height: 22),
          StaggerIn(index: i++, child: _quickActions()),
          const SizedBox(height: 22),
          StaggerIn(index: i++, child: _supportCard()),
        ],
      ),
    );
  }

  Widget _statsRow() {
    final balance = widget.data.balance;
    final covered = monthsCovered(balance, _fee);
    String? feeNote;
    var feeWarn = false;
    if (covered != null) {
      if (covered == 0) {
        feeNote = 'не хватит на следующий месяц';
        feeWarn = true;
      } else if (covered == 1) {
        feeNote = 'хватит примерно на месяц';
      } else {
        feeNote = 'хватит примерно на $covered ${_plural(covered, 'месяц', 'месяца', 'месяцев')}';
      }
    }

    final topUp = _lastTopUp;
    final topUpDate = topUp == null ? null : parseBillingDate(topUp.date);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_extrasLoading || _fee != null)
            Expanded(
              child: _StatTile(
                label: 'Абонплата',
                loading: _extrasLoading,
                value: _fee == null ? '' : BalanceStore.format(_fee!),
                suffix: '/мес',
                note: feeNote,
                noteColor: feeWarn ? AppColors.danger : null,
                onTap: () => widget.onOpenTab(1),
              ),
            ),
          if ((_extrasLoading || _fee != null) &&
              (_extrasLoading || topUp != null))
            const SizedBox(width: 12),
          if (_extrasLoading || topUp != null)
            Expanded(
              child: _StatTile(
                label: 'Пополнение',
                loading: _extrasLoading,
                value: topUp == null ? '' : signedMoney(topUp.amount),
                valueColor: AppColors.ok,
                note: topUpDate == null ? topUp?.date : shortDate(topUpDate),
                onTap: () => widget.onOpenTab(3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    void push(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PillSectionHeader('Быстрые действия'),
        Row(
          children: [
            _QuickAction(
              icon: Icons.speed_rounded,
              label: 'Тест сети',
              onTap: () => push(const DiagnosticsScreen()),
            ),
            _QuickAction(
              icon: Icons.devices_other_rounded,
              label: 'Кто в Wi-Fi',
              onTap: () => push(const LanDevicesScreen()),
            ),
            _QuickAction(
              icon: Icons.tune_rounded,
              label: 'Услуги',
              onTap: () => widget.onOpenTab(1),
            ),
            _QuickAction(
              icon: Icons.live_tv_rounded,
              label: 'ТВ',
              onTap: () => widget.onOpenTab(2),
            ),
          ],
        ),
      ],
    );
  }

  Widget _supportCard() {
    final p = context.p;
    return Pressable(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SupportScreen())),
      semanticLabel: 'Поддержка',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: cardBox(context, radius: 20),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.headset_mic_rounded, color: p.ink, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Поддержка',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: p.ink)),
                  const SizedBox(height: 2),
                  Text(AppConfig.supportPhoneHuman,
                      style: TextStyle(
                          fontSize: 13,
                          color: p.inkMute,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
            _RoundIconButton(
              icon: Icons.call_rounded,
              tooltip: 'Позвонить',
              onTap: () => launchUrl(Uri.parse('tel:${AppConfig.supportPhone}')),
            ),
          ],
        ),
      ),
    );
  }

  static String _plural(int n, String one, String few, String many) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return one;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
    return many;
  }
}

/// главная карточка: баланс крупно, статус, тариф и оплата
class _BalanceHero extends StatelessWidget {
  final CabinetData data;
  final bool refreshing;
  final VoidCallback onPay;
  final VoidCallback onPickAccount;
  final VoidCallback onHistory;

  const _BalanceHero({
    required this.data,
    required this.refreshing,
    required this.onPay,
    required this.onPickAccount,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final restricted = data.isRestricted || data.balance < 0;
    final hasTariff = data.tariff.isNotEmpty &&
        data.tariff != 'Нет тарифа' &&
        data.tariff != 'Неизвестный тариф';
    final account =
        (data.account.isNotEmpty && data.account != '—') ? data.account : null;
    final multi = data.accounts.length > 1;

    final details = [
      if (hasTariff) data.tariff,
      if (data.address.isNotEmpty) data.address,
    ].join('  ·  ');

    const radius = 26.0;
    return BorderBeam(
      active: refreshing,
      radius: radius,
      color: Colors.white.withValues(alpha: 0.9),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: brandGradient(dark),
          boxShadow: dark
              ? null
              : [
                  BoxShadow(
                    color: AppColors.brandInk.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: multi
                      ? _HeroChip(
                          label: account != null ? 'Договор $account' : 'Договор',
                          icon: Icons.unfold_more_rounded,
                          onTap: onPickAccount,
                        )
                      : _CopyChip(account: account),
                ),
                const SizedBox(width: 12),
                PulseDot(
                  color: restricted
                      ? const Color(0xFFFF8A80)
                      : const Color(0xFF5CF0A8),
                  label: restricted ? 'Ограничен' : 'Активен',
                  onBrand: true,
                  size: 7,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Баланс',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SlidingNumber(
                value: data.balance,
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1.2,
                  height: 1.15,
                ),
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
            if (restricted) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data.recommendedPayment != null
                            ? 'Услуги приостановлены. Для включения внесите ${data.recommendedPayment}'
                            : 'Услуги приостановлены. Пополните баланс, чтобы включить',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Pressable(
                    onTap: onPay,
                    semanticLabel: 'Пополнить баланс',
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded,
                              size: 20, color: AppColors.brandInk),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              restricted && data.recommendedPayment != null
                                  ? 'Оплатить ${data.recommendedPayment}'
                                  : 'Пополнить',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Pressable(
                  onTap: onHistory,
                  semanticLabel: 'История операций',
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _HeroChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.85)),
          ],
        ),
      ),
    );
  }
}

/// номер договора с копированием: иконка морфится в галочку
class _CopyChip extends StatefulWidget {
  final String? account;
  const _CopyChip({required this.account});

  @override
  State<_CopyChip> createState() => _CopyChipState();
}

class _CopyChipState extends State<_CopyChip> {
  bool _copied = false;

  void _copy() {
    final a = widget.account;
    if (a == null) return;
    Clipboard.setData(ClipboardData(text: a));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    return Pressable(
      onTap: a == null ? null : _copy,
      semanticLabel: a == null ? null : 'Скопировать номер договора',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: _copied ? 0.26 : 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              a == null ? 'Договор' : 'Договор $a',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (a != null) ...[
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (c, an) => ScaleTransition(scale: an, child: c),
                child: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  key: ValueKey(_copied),
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final bool loading;
  final String value;
  final String? suffix;
  final Color? valueColor;
  final String? note;
  final Color? noteColor;
  final VoidCallback? onTap;

  const _StatTile({
    required this.label,
    required this.loading,
    required this.value,
    this.suffix,
    this.valueColor,
    this.note,
    this.noteColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Pressable(
      onTap: loading ? null : onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: cardBox(context, radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: p.inkMute)),
            const SizedBox(height: 8),
            if (loading) ...[
              const SkeletonBox(width: 86, height: 22),
              const SizedBox(height: 8),
              const SkeletonBox(width: 110, height: 12),
            ] else ...[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: valueColor ?? p.ink,
                      ),
                    ),
                    if (suffix != null)
                      TextSpan(
                        text: ' $suffix',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: p.inkMute,
                        ),
                      ),
                  ]),
                  style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 4),
                Text(
                  note!,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: noteColor ?? p.inkFaint,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        semanticLabel: label,
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: cardBox(context, radius: 20),
              child: Icon(icon,
                  size: 26, color: dark ? AppColors.brand : AppColors.brandInk),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: p.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundIconButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        scale: 0.9,
        semanticLabel: tooltip,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: AppColors.brand,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onTap;

  const _Notice({
    required this.icon,
    required this.text,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Pressable(
      onTap: onTap,
      semanticLabel: text,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: p.ink)),
            ),
            Text(action,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent)),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
