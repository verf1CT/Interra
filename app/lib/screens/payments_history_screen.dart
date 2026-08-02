import 'package:flutter/material.dart';
import '../services/cabinet_parser.dart';
import '../services/auth_store.dart';
import '../theme.dart';

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
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

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
          _error = 'Не удалось загрузить историю платежей.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: Text('История платежей пуста', style: TextStyle(color: context.p.inkMute)),
      );
    }

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _payments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _payments[index];
          final isPositive = item.amount > 0;
          return Container(
            padding: const EdgeInsets.all(16),
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
                    color: isPositive ? AppColors.brand.withValues(alpha: 0.1) : AppColors.danger.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPositive ? Icons.arrow_downward : Icons.arrow_upward,
                    color: isPositive ? AppColors.brand : AppColors.danger,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.date,
                        style: TextStyle(fontWeight: FontWeight.w600, color: context.p.ink),
                      ),
                      if (item.comment.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.comment,
                          style: TextStyle(fontSize: 13, color: context.p.inkMute),
                        ),
                      ]
                    ],
                  ),
                ),
                Text(
                  '${isPositive ? '+' : ''}${item.amount.toStringAsFixed(2)} ₽',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isPositive ? AppColors.brand : AppColors.danger,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
