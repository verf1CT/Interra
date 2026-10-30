import 'package:flutter/material.dart';
import '../services/cabinet_parser.dart';
import '../services/demo_mode.dart';
import '../services/auth_store.dart';
import '../theme.dart';

class PaymentsHistoryScreen extends StatefulWidget {
  const PaymentsHistoryScreen({super.key});

  @override
  State<PaymentsHistoryScreen> createState() => _PaymentsHistoryScreenState();
}

class _PaymentsHistoryScreenState extends State<PaymentsHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  String? _error;
  List<PaymentItem> _payments = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    DemoMode.isEnabled.addListener(_onDemoChanged);
    _loadData();
  }

  void _onDemoChanged() {
    if (mounted) _loadData();
  }

  @override
  void dispose() {
    DemoMode.isEnabled.removeListener(_onDemoChanged);
    _tabController.dispose();
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

  double get _totalPaymentsThisMonth {
    double sum = 0.0;
    for (final p in _payments) {
      if (p.amount > 0) sum += p.amount;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Табы: операции / сессии (как на сайте)
        Container(
          color: context.p.bg,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.brand,
            unselectedLabelColor: context.p.inkMute,
            indicatorColor: AppColors.brand,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Операции'),
              Tab(text: 'Сессии'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOperationsTab(),
              _buildSessionsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOperationsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.brand));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: context.p.ink)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 48, color: context.p.inkMute),
            const SizedBox(height: 12),
            Text('История операций пуста', style: TextStyle(color: context.p.inkMute)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Сводка платежей (как на Скриншоте 1)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: context.p.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.p.line),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Платежей за текущий месяц:',
                  style: TextStyle(fontSize: 13, color: context.p.inkMute, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${_totalPaymentsThisMonth.toStringAsFixed(0)} руб.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _totalPaymentsThisMonth > 0 ? AppColors.brand : context.p.ink,
                  ),
                ),
              ],
            ),
          ),

          ..._payments.map((item) {
            final isZero = item.amount == 0;
            final isPositive = item.amount > 0;
            final opName = item.operation.isNotEmpty
                ? item.operation
                : (item.comment.isNotEmpty ? item.comment : 'Операция');

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.p.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.p.line),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isZero
                          ? context.p.line
                          : (isPositive
                              ? AppColors.brand.withValues(alpha: 0.1)
                              : AppColors.danger.withValues(alpha: 0.1)),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isZero
                          ? Icons.info_outline_rounded
                          : (isPositive ? Icons.arrow_downward : Icons.arrow_upward),
                      color: isZero
                          ? context.p.inkMute
                          : (isPositive ? AppColors.brand : AppColors.danger),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: context.p.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.date,
                          style: TextStyle(fontSize: 12, color: context.p.inkMute),
                        ),
                        if (item.operator.isNotEmpty && item.operator != 'SYSTEM') ...[
                          const SizedBox(height: 2),
                          Text(
                            'Оператор: ${item.operator}',
                            style: TextStyle(fontSize: 11, color: context.p.inkMute),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isZero)
                    Text(
                      '${isPositive ? '+' : ''}${item.amount.toStringAsFixed(2)} ₽',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isPositive ? AppColors.brand : AppColors.danger,
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: context.p.line,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '0.00 ₽',
                        style: TextStyle(fontSize: 12, color: context.p.inkMute, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSessionsTab() {
    if (DemoMode.isEnabled.value) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: DemoMode.demoSessions.length,
        itemBuilder: (context, index) {
          final s = DemoMode.demoSessions[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.p.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: s.isActive ? AppColors.brand : context.p.line,
                width: s.isActive ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.router_rounded,
                          size: 20,
                          color: s.isActive ? AppColors.brand : context.p.inkMute,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          s.ip,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.p.ink,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: s.isActive
                            ? const Color(0xFF10B981).withValues(alpha: 0.12)
                            : context.p.line,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.isActive ? 'Активна сейчас' : 'Завершена',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: s.isActive ? const Color(0xFF10B981) : context.p.inkMute,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Подключение', style: TextStyle(fontSize: 11, color: context.p.inkMute)),
                        const SizedBox(height: 2),
                        Text(s.startedAt, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.p.ink)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('Длительность', style: TextStyle(fontSize: 11, color: context.p.inkMute)),
                        const SizedBox(height: 2),
                        Text(s.duration, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.p.ink)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Трафик (Вх/Исх)', style: TextStyle(fontSize: 11, color: context.p.inkMute)),
                        const SizedBox(height: 2),
                        Text('${s.rxBytes} / ${s.txBytes}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brand)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_rounded, size: 48, color: context.p.inkMute),
            const SizedBox(height: 12),
            Text(
              'Интернет-сессии',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.p.ink),
            ),
            const SizedBox(height: 6),
            Text(
              'Активные интернет-сессии отсутствуют. Сессии фиксируются автоматически при подключении оборудования.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.p.inkMute),
            ),
          ],
        ),
      ),
    );
  }
}
