import 'package:flutter/material.dart';
import '../services/cabinet_parser.dart';
import '../services/demo_mode.dart';
import '../services/auth_store.dart';
import '../theme.dart';
import '../utils/billing_math.dart';
import '../widgets/design_system.dart';
import '../widgets/motion_kit.dart';

class PaymentsHistoryScreen extends StatefulWidget {
  const PaymentsHistoryScreen({super.key});

  @override
  State<PaymentsHistoryScreen> createState() => _PaymentsHistoryScreenState();
}

class _PaymentsHistoryScreenState extends State<PaymentsHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<PaymentItem> _payments = [];

  @override
  void initState() {
    super.initState();
    DemoMode.isEnabled.addListener(_onDemoChanged);
    _loadData();
  }

  void _onDemoChanged() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    DemoMode.isEnabled.removeListener(_onDemoChanged);
    super.dispose();
  }



  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    if (DemoMode.isEnabled.value) {
      if (mounted) {
        setState(() {
          _payments = DemoMode.demoPayments;
          _loading = false;
          _error = null;
        });
      }
      return;
    }

    try {
      final token = await AuthStore().appToken;
      if (token == null) throw Exception('No token');

      final payments = await CabinetParser.fetchPayments(token);

      if (mounted) {
        setState(() {
          _payments = payments;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Не удалось загрузить историю операций.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _buildOperationsTab();

  Widget _centerState({
    required IconData icon,
    required String title,
    String? text,
    Widget? action,
  }) {
    final p = context.p;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: p.surfaceAlt, shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: p.inkMute),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.ink)),
            if (text != null) ...[
              const SizedBox(height: 6),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: p.inkMute, height: 1.4)),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              SizedBox(width: 200, child: action),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOperationsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.brand));
    }

    if (_error != null) {
      return _centerState(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        action: FilledButton(onPressed: _loadData, child: const Text('Повторить')),
      );
    }

    if (_payments.isEmpty) {
      return _centerState(
        icon: Icons.receipt_long_rounded,
        title: 'Операций пока нет',
        text: 'Здесь появятся пополнения и списания по договору',
      );
    }

    // группировка по месяцам, порядок как отдал биллинг (новые сверху)
    final groups = <String, List<PaymentItem>>{};
    final groupDates = <String, DateTime?>{};
    for (final p in _payments) {
      final d = parseBillingDate(p.date);
      final key = d == null ? 'Другое' : monthTitle(d);
      groups.putIfAbsent(key, () => []).add(p);
      groupDates.putIfAbsent(key, () => d);
    }
    final latest = groupDates.values.whereType<DateTime>().fold<DateTime?>(
        null, (a, b) => a == null || b.isAfter(a) ? b : a);

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          if (latest != null) ...[
            StaggerIn(index: 0, child: _MonthSummary(
              month: latest,
              totals: totalsForMonth(_payments, latest.year, latest.month),
            )),
            const SizedBox(height: 22),
          ],
          for (final (gi, e) in groups.entries.indexed) ...[
            PillSectionHeader(e.key),
            StaggerIn(
              index: gi + 1,
              child: PillGroupCard(
                children: [
                  for (var i = 0; i < e.value.length; i++) ...[
                    if (i > 0) const PillDivider(),
                    _OperationRow(item: e.value[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  final DateTime month;
  final MonthTotals totals;
  const _MonthSummary({required this.month, required this.totals});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget col(String label, double v, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12.5, color: p.inkMute)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  v == 0 ? '0 ₽' : signedMoney(v),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: v == 0 ? p.inkFaint : color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: cardBox(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(monthTitle(month),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink)),
          const SizedBox(height: 14),
          Row(
            children: [
              col('Пополнения', totals.income, AppColors.ok),
              Container(width: 1, height: 40, color: p.line),
              const SizedBox(width: 18),
              col('Списания', totals.expense, p.ink),
            ],
          ),
        ],
      ),
    );
  }
}

class _OperationRow extends StatelessWidget {
  final PaymentItem item;
  const _OperationRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final income = item.amount > 0;
    final zero = item.amount == 0;
    final title = item.operation.isNotEmpty
        ? item.operation
        : (item.comment.isNotEmpty ? item.comment : 'Операция');
    final d = parseBillingDate(item.date);
    final when = d == null
        ? item.date
        : [shortDate(d), shortTime(d)].where((s) => s.isNotEmpty).join(', ');
    final who = item.operator.isNotEmpty && item.operator != 'SYSTEM' ? item.operator : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: income ? AppColors.ok.withValues(alpha: 0.12) : p.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(
              zero
                  ? Icons.info_outline_rounded
                  : (income ? Icons.south_west_rounded : Icons.north_east_rounded),
              size: 18,
              color: income ? AppColors.ok : p.inkMute,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700, color: p.ink, height: 1.25)),
                const SizedBox(height: 3),
                Text(who == null ? when : '$when  ·  $who',
                    style: TextStyle(fontSize: 12.5, color: p.inkMute)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            zero ? '0 ₽' : signedMoney(item.amount),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: zero ? p.inkFaint : (income ? AppColors.ok : p.ink),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
