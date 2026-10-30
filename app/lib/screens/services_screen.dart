import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/cabinet_parser.dart';
import '../services/demo_mode.dart';
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
          _services = DemoMode.demoServices;
          _loading = false;
          _error = null;
        });
      }
      return;
    }

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
    if (DemoMode.isEnabled.value) {
      if (mounted) {
        setState(() {
          _services = DemoMode.demoServices;
          _loading = false;
          _error = null;
        });
      }
      return;
    }

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
          // Блок паспорта (скрыт в демо-режиме для скриншотов)
          if (!DemoMode.isEnabled.value)
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
                      label: const Text('Открыть кабинет на сайте'),
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

          if (DemoMode.isEnabled.value) ...[
            const SizedBox(height: 20),
            Text(
              'Доступные тарифные планы',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.p.ink,
              ),
            ),
            const SizedBox(height: 12),
            ...DemoMode.availableTariffs.map((t) => _buildDemoTariffCard(t)),
            const SizedBox(height: 20),
            Text(
              'Дополнительные услуги',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.p.ink,
              ),
            ),
            const SizedBox(height: 12),
            _buildExtraOption('Статический IP-адрес', '150 ₽ / мес', Icons.public_rounded),
            const SizedBox(height: 10),
            _buildExtraOption('Аренда гигабитного роутера Wi-Fi 6', '99 ₽ / мес', Icons.router_rounded),
            const SizedBox(height: 10),
            _buildExtraOption('Антивирус Kaspersky Safe Kids', '99 ₽ / мес', Icons.security_rounded),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildDemoTariffCard(DemoTariff t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: t.isCurrent ? AppColors.brand : context.p.line,
          width: t.isCurrent ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  t.speed,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (t.badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: t.isCurrent
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    t.badge!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: t.isCurrent ? const Color(0xFF10B981) : AppColors.accent,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                t.price,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.p.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t.title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: context.p.ink,
            ),
          ),
          const SizedBox(height: 8),
          ...t.features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Text(
                    f,
                    style: TextStyle(fontSize: 13, color: context.p.inkMute),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: t.isCurrent
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Текущий тарифный план'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  )
                : FilledButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Заявка на подключение тарифа «${t.title}» отправлена')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Подключить', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtraOption(String title, String price, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.p.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: AppColors.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.p.ink),
            ),
          ),
          Text(
            price,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.p.inkMute),
          ),
        ],
      ),
    );
  }
}
