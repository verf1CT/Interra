import 'package:flutter/material.dart';
import '../services/cabinet_parser.dart';
import '../services/auth_store.dart';
import '../theme.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  bool _loading = true;
  String? _error;
  List<ServiceItem> _services = [];

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
      
      final services = await CabinetParser.fetchServices(token);
      
      if (mounted) {
        setState(() {
          _services = services;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Не удалось загрузить список услуг.';
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

    if (_services.isEmpty) {
      return Center(
        child: Text('Услуги не найдены', style: TextStyle(color: context.p.inkMute)),
      );
    }

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _services.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _services[index];
          final isActive = item.status.toLowerCase().contains('актив') || item.status.toLowerCase().contains('включ');
          
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.p.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.p.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: context.p.ink),
                      ),
                    ),
                    if (item.cost.isNotEmpty)
                      Text(
                        item.cost,
                        style: TextStyle(fontWeight: FontWeight.bold, color: context.p.inkMute),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.brand.withValues(alpha: 0.1) : context.p.line,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.status.isNotEmpty ? item.status : 'Неизвестно',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isActive ? AppColors.brand : context.p.inkMute,
                    ),
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
