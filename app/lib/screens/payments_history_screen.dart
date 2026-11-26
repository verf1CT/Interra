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

  /// самый старый загруженный месяц: «показать раньше» грузит предыдущий
  DateTime _cursor = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loadingMore = false;
  bool _moreFailed = false;

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



  DateTime get _prevMonth => DateTime(_cursor.year, _cursor.month - 1);

  bool get _canLoadMore {
    final from = CabinetParser.reportsFromYear;
    return !DemoMode.isEnabled.value && from != null && _prevMonth.year >= from;
  }

  /// листаем назад по месяцу; пустые месяцы пропускаем, но не больше полугода
  /// за одно нажатие, чтобы не висеть на десятке запросов
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final token = await AuthStore().appToken;
      if (token == null) throw Exception('No token');
      for (var i = 0; i < 6 && _canLoadMore; i++) {
        final m = _prevMonth;
        final items = await CabinetParser.fetchPaymentsMonth(token, m.year, m.month);
        if (!mounted) return;
        setState(() {
          _cursor = m;
          _payments = [..._payments, ...items];
        });
        if (items.isNotEmpty) break;
      }
    } catch (_) {
      if (mounted) setState(() => _moreFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _cursor = DateTime(DateTime.now().year, DateTime.now().month);
      _moreFailed = false;
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
        title: _cursor.month == DateTime.now().month && _cursor.year == DateTime.now().year
            ? 'В этом месяце операций нет'
            : 'Операций пока нет',
        text: 'Здесь появятся пополнения и списания по договору',
        action: _canLoadMore ? _moreButton() : null,
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
            StaggerIn(index: gi + 1, child: _MonthCard(items: e.value)),
            const SizedBox(height: 18),
          ],
          if (_canLoadMore) _moreButton(),
        ],
      ),
    );
  }

  Widget _moreButton() {
    final label = _moreFailed
        ? 'Не загрузилось, ещё раз'
        : 'Показать ${monthTitle(_prevMonth).toLowerCase()}';
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: _loadingMore ? null : _loadMore,
        child: _loadingMore
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
            : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// месяц операций: движение денег сверху, записи по 0 ₽ (смена статуса,
/// создание услуги) свёрнуты в одну строку - их почти никто не читает
class _MonthCard extends StatefulWidget {
  final List<PaymentItem> items;
  const _MonthCard({required this.items});

  @override
  State<_MonthCard> createState() => _MonthCardState();
}

class _MonthCardState extends State<_MonthCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final money = widget.items.where((e) => e.amount != 0).toList();
    final service = widget.items.where((e) => e.amount == 0).toList();
    final rows = <Widget>[
      for (final item in money) _OperationRow(item: item),
      if (service.isNotEmpty)
        Pressable(
          onTap: () => setState(() => _open = !_open),
          semanticLabel: _open ? 'Свернуть служебные записи' : 'Показать служебные записи',
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Служебные записи · ${service.length}',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.inkMute),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(Icons.expand_more_rounded, size: 20, color: p.inkMute),
                ),
              ],
            ),
          ),
        ),
      if (_open)
        for (final item in service) _OperationRow(item: item),
    ];
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: PillGroupCard(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const PillDivider(),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// названия операций UTM5 по-человечески. неизвестные оставляем как есть
@visibleForTesting
String operationTitle(PaymentItem item) {
  final op = item.operation.trim().toLowerCase();
  if (op == 'активация услуги' && item.amount < 0) return 'Абонплата';
  if (op == 'оплата' && item.amount > 0) return 'Пополнение';
  final raw = item.operation.trim().isNotEmpty
      ? item.operation.trim()
      : (item.comment.trim().isNotEmpty ? item.comment.trim() : 'Операция');
  return raw[0].toUpperCase() + raw.substring(1);
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
    final title = operationTitle(item);
    final d = parseBillingDate(item.date);
    final when = d == null
        ? item.date
        : [shortDate(d), shortTime(d)].where((s) => s.isNotEmpty).join(', ');
    final comment = item.comment.trim();
    final note = comment.isNotEmpty &&
            comment.toLowerCase() != item.operation.trim().toLowerCase() &&
            comment.toLowerCase() != title.toLowerCase()
        ? comment
        : null;
    final who = item.operator.isNotEmpty && item.operator != 'SYSTEM' ? item.operator : null;
    final sub = [when, note, who].whereType<String>().join('  ·  ');

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
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
