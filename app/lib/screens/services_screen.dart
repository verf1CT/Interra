import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/cabinet_parser.dart';
import '../services/auth_store.dart';
import '../widgets/passport_form_sheet.dart';
import '../theme.dart';

class ServicesScreen extends StatefulWidget {
  final VoidCallback? onOpenPassportForm;

  const ServicesScreen({super.key, this.onOpenPassportForm});

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

  void _openPassport() {
    PassportFormSheet.show(context, onSaved: () {
      _loadData();
      widget.onOpenPassportForm?.call();
    });
  }

  Future<void> _openWebCabinet() async {
    try {
      final token = await AuthStore().appToken;
      if (token == null) return;
      final url = await CabinetParser.getTariffsWebUrl(token);
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
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

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Блок паспорта как на Скриншоте 3
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.brand.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.assignment_ind_rounded, color: AppColors.brand, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Заказ и смена тарифа',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.p.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Для выбора и подключения тарифного плана необходимо подтвердить паспортные данные в соответствии с требованиями законодательства РФ (ФЗ «О связи»).',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.p.inkMute,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _openPassport,
                      icon: const Icon(Icons.edit_document, size: 18),
                      label: const Text('Ввести паспортные данные'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openWebCabinet,
                      icon: const Icon(Icons.open_in_browser, size: 18),
                      label: const Text('Заполнить на сайте'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Подключённые тарифы и услуги',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.p.ink,
            ),
          ),
          const SizedBox(height: 12),

          if (_services.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.p.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.p.line),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 36, color: context.p.inkMute),
                    const SizedBox(height: 8),
                    Text(
                      'Активный тариф не подключён',
                      style: TextStyle(fontWeight: FontWeight.w600, color: context.p.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Заполните паспортные данные выше для активации тарифа',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: context.p.inkMute),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._services.map((item) {
              final isActive = item.status.toLowerCase().contains('актив') ||
                  item.status.toLowerCase().contains('включ');

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
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
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: context.p.ink,
                            ),
                          ),
                        ),
                        if (item.cost.isNotEmpty)
                          Text(
                            item.cost,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.p.inkMute,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.brand.withValues(alpha: 0.1)
                            : context.p.line,
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
            }),
        ],
      ),
    );
  }
}
