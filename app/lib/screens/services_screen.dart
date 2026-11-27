import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/cabinet_parser.dart';
import '../services/demo_mode.dart';
import '../services/auth_store.dart';
import '../widgets/passport_form_sheet.dart';
import '../theme.dart';
import '../services/balance_store.dart';
import '../utils/billing_math.dart';
import '../widgets/design_system.dart';
import '../widgets/motion_kit.dart';
import 'tariffs_screen.dart';

class ServicesScreen extends StatefulWidget {
  final VoidCallback? onOpenPassportForm;

  /// биллинг просит паспортные данные у этого договора
  final bool needsPassport;

  const ServicesScreen({super.key, this.onOpenPassportForm, this.needsPassport = false});

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
      return _ErrorState(message: _error!, onRetry: _loadData);
    }

    // основной тариф - первая услуга с месячной ценой, остальное - список
    final mainIdx = _services.indexWhere((s) => s.cost.toLowerCase().contains('мес'));
    final main = mainIdx >= 0 ? _services[mainIdx] : null;
    final rest = [
      for (var i = 0; i < _services.length; i++)
        if (i != mainIdx) _services[i],
    ];
    final fee = monthlyFee(_services);

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (main != null) ...[
            StaggerIn(index: 0, child: _TariffHero(item: main)),
            const SizedBox(height: 22),
          ],
          if (_services.isEmpty) StaggerIn(index: 0, child: _EmptyServices(needsPassport: widget.needsPassport)),
          if (rest.isNotEmpty) ...[
            const PillSectionHeader('Подключено'),
            StaggerIn(
              index: 1,
              child: PillGroupCard(
                children: [
                  for (var i = 0; i < rest.length; i++) ...[
                    if (i > 0) const PillDivider(),
                    _ServiceRow(item: rest[i]),
                  ],
                ],
              ),
            ),
          ],
          if (fee != null && _services.length > 1) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Text('Итого в месяц',
                      style: TextStyle(fontSize: 13, color: context.p.inkMute)),
                  const Spacer(),
                  Text(
                    BalanceStore.format(fee),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.p.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          const PillSectionHeader('Смена тарифа'),
          StaggerIn(
            index: 2,
            child: _ChangeTariffCard(
              needsPassport: widget.needsPassport,
              onPassport: _openPassport,
              onWeb: _openWebCabinet,
              onTariffs: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const TariffsScreen())),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Комфорт 200 (Безлимитный интернет 200 Мбит/с)» -> заголовок и пояснение
(String, String?) _splitName(String name) {
  final t = name.trim();
  final i = t.indexOf('(');
  if (i <= 0 || !t.endsWith(')')) return (t, null);
  final title = t.substring(0, i).trim();
  final sub = t.substring(i + 1, t.length - 1).trim();
  return (title, sub.isEmpty ? null : sub);
}

bool _isActive(ServiceItem s) {
  final st = s.status.toLowerCase();
  return st.contains('актив') || st.contains('включ');
}

IconData _iconFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('тв') || n.contains('телекан')) return Icons.live_tv_rounded;
  if (n.contains('домофон') || n.contains('камер')) return Icons.videocam_rounded;
  if (n.contains('ip') || n.contains('адрес')) return Icons.dns_rounded;
  if (n.contains('интернет') || n.contains('мбит')) return Icons.wifi_rounded;
  return Icons.widgets_rounded;
}

class _TariffHero extends StatelessWidget {
  final ServiceItem item;
  const _TariffHero({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (title, sub) = _splitName(item.name);
    final m = RegExp(r'^(.*?)\s*/\s*(мес.*)$').firstMatch(item.cost.trim());
    final price = m?.group(1) ?? item.cost;
    final per = m?.group(2);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: cardBox(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ваш тариф',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.inkMute)),
          const SizedBox(height: 10),
          Text(title,
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: p.ink,
                  height: 1.15)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(fontSize: 14, color: p.inkMute, height: 1.3)),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(_iconFor(item.name),
                    size: 20, color: dark ? AppColors.brand : AppColors.brandInk),
                const SizedBox(width: 10),
                Text('Абонплата', style: TextStyle(fontSize: 13.5, color: p.inkMute)),
                const Spacer(),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: price,
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800, color: p.ink),
                    ),
                    if (per != null)
                      TextSpan(
                        text: ' / $per',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: p.inkMute),
                      ),
                  ]),
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final ServiceItem item;
  const _ServiceRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (title, sub) = _splitName(item.name);
    final active = _isActive(item);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconFor(item.name),
                size: 20, color: dark ? AppColors.brand : AppColors.brandInk),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: p.ink)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 12.5, color: p.inkMute)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (item.cost.isNotEmpty)
                Text(item.cost,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: p.ink)),
              // статус показываем, только если его написал биллинг
              if (item.status.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.status,
                  style: TextStyle(fontSize: 12, color: active ? AppColors.ok : p.inkMute),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangeTariffCard extends StatelessWidget {
  final bool needsPassport;
  final VoidCallback onPassport;
  final VoidCallback onWeb;
  final VoidCallback onTariffs;
  const _ChangeTariffCard({
    required this.needsPassport,
    required this.onPassport,
    required this.onWeb,
    required this.onTariffs,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardBox(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            needsPassport
                ? 'Чтобы выбрать или сменить тариф, нужны паспортные данные - этого требует закон «О связи»'
                : 'Новый тариф начнёт действовать после окончания текущего периода',
            style: TextStyle(fontSize: 13.5, color: p.inkMute, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (needsPassport) ...[
            FilledButton(
              onPressed: onPassport,
              child: const Text('Ввести паспортные данные'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onWeb,
              child: const Text('Открыть кабинет на сайте'),
            ),
          ] else
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: onTariffs,
                child: const Text('Выбрать тариф'),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyServices extends StatelessWidget {
  final bool needsPassport;
  const _EmptyServices({required this.needsPassport});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: cardBox(context, radius: 22),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: p.surfaceAlt, shape: BoxShape.circle),
            child: Icon(Icons.wifi_off_rounded, size: 26, color: p.inkMute),
          ),
          const SizedBox(height: 14),
          Text('Тариф не подключён',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.ink)),
          const SizedBox(height: 4),
          Text(
            needsPassport
                ? 'Заполните паспортные данные ниже, чтобы выбрать тариф'
                : 'Выбрать тариф можно в кабинете на сайте',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: p.inkMute, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
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
              child: Icon(Icons.cloud_off_rounded, size: 28, color: p.inkMute),
            ),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink)),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: FilledButton(onPressed: onRetry, child: const Text('Повторить')),
            ),
          ],
        ),
      ),
    );
  }
}
