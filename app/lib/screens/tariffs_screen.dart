import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_store.dart';
import '../services/balance_store.dart';
import '../services/cabinet_parser.dart';
import '../services/demo_mode.dart';
import '../theme.dart';
import '../widgets/app_sheets.dart';
import '../widgets/design_system.dart';
import '../widgets/motion_kit.dart';

/// выбор следующего тарифа: группы и тарифы со страницы aaatarif выбранного
/// счёта. новый тариф биллинг включает после окончания текущего периода
class TariffsScreen extends StatefulWidget {
  const TariffsScreen({super.key});

  @override
  State<TariffsScreen> createState() => _TariffsScreenState();
}

class _TariffsScreenState extends State<TariffsScreen> {
  bool _loading = true;
  TariffCatalog? _catalog;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    TariffCatalog? c;
    if (DemoMode.isEnabled.value) {
      c = DemoMode.demoTariffs;
    } else {
      try {
        final token = await AuthStore().appToken;
        if (token != null) c = await CabinetParser.fetchTariffs(token);
      } catch (e) {
        debugPrint('тарифы не загрузились: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _catalog = c;
      _loading = false;
    });
  }

  void _open(TariffOffer offer, TariffGroup group) {
    showAppSheet<void>(
      context,
      _OfferSheet(offer: offer, group: group, current: offer.name == _catalog?.current),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Тарифы')),
      body: _body(),
    );
  }

  Widget _body() {
    final p = context.p;
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: const [
          SkeletonBox(width: double.infinity, height: 40),
          SizedBox(height: 22),
          SkeletonBox(width: double.infinity, height: 260, radius: 22),
        ],
      );
    }
    final c = _catalog;
    final groups = c?.groups.where((g) => (c.offers[g.id] ?? const []).isNotEmpty).toList() ?? const [];
    if (c == null || groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Не удалось загрузить тарифы',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.ink)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }

    final paid = groups.where((g) => !g.isNoTariff).toList();
    final none = groups.where((g) => g.isNoTariff).toList();
    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Новый тариф начнёт действовать, когда закончится текущий. '
              'Если ничего не выбрать, текущий продлится сам',
              style: TextStyle(fontSize: 13.5, color: p.inkMute, height: 1.4),
            ),
          ),
          const SizedBox(height: 20),
          for (final g in paid) ...[
            PillSectionHeader(g.name),
            PillGroupCard(children: [
              for (final (k, o) in c.offers[g.id]!.indexed) ...[
                if (k > 0) const PillDivider(),
                _OfferRow(offer: o, current: o.name == c.current, onTap: () => _open(o, g)),
              ],
            ]),
            const SizedBox(height: 18),
          ],
          for (final g in none) ...[
            PillGroupCard(children: [
              _OfferRow(
                offer: c.offers[g.id]!.first,
                current: c.current == null,
                note: g.note,
                onTap: () => _open(c.offers[g.id]!.first, g),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// «за 456 дней», «за 30 дней»
String _days(int n) {
  final m10 = n % 10, m100 = n % 100;
  final w = (m10 == 1 && m100 != 11)
      ? 'день'
      : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14))
          ? 'дня'
          : 'дней';
  return 'за $n $w';
}

class _OfferRow extends StatelessWidget {
  final TariffOffer offer;
  final bool current;
  final String? note;
  final VoidCallback onTap;

  const _OfferRow({required this.offer, required this.current, this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final sub = [
      if (offer.days != null) _days(offer.days!),
      if (offer.perMonth != null) '${BalanceStore.format(offer.perMonth!.toDouble())} в месяц',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.name,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.ink)),
                    if (current) ...[
                      const SizedBox(height: 2),
                      const Text('Действует сейчас',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.brand)),
                    ] else if (sub.isNotEmpty || note != null) ...[
                      const SizedBox(height: 2),
                      Text(sub.isNotEmpty ? sub : note!,
                          style: TextStyle(fontSize: 12.5, color: p.inkMute, height: 1.3)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (offer.price != null)
                Text(
                  BalanceStore.format(offer.price!.toDouble()),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: p.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// шторка тарифа: цена, описание биллинга и выбор. как биллинг принимает
/// выбор, пока не видели, поэтому выбор завершается на его странице в браузере
class _OfferSheet extends StatefulWidget {
  final TariffOffer offer;
  final TariffGroup group;
  final bool current;

  const _OfferSheet({required this.offer, required this.group, required this.current});

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  bool _confirm = false;

  Future<void> _openBilling() async {
    final url = CabinetParser.tariffWebUrl(widget.offer);
    Navigator.of(context).pop();
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('не открылась страница тарифа: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final o = widget.offer;
    final none = widget.group.isNoTariff;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(o.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.ink)),
        if (o.price != null) ...[
          const SizedBox(height: 4),
          Text(
            [BalanceStore.format(o.price!.toDouble()), if (o.days != null) _days(o.days!)].join(' '),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: p.inkMute,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (o.details.isNotEmpty || (none && widget.group.note != null)) ...[
          const SizedBox(height: 14),
          for (final line in none ? [widget.group.note!] : o.details)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line, style: TextStyle(fontSize: 14, color: p.ink, height: 1.35)),
            ),
        ],
        const SizedBox(height: 14),
        ..._actions(),
      ],
    );
  }

  List<Widget> _actions() {
    final p = context.p;
    final o = widget.offer;
    final none = widget.group.isNoTariff;
    if (widget.current) {
      return [
        Text(
          none ? 'Сейчас тарифа нет' : 'Это ваш тариф. Если ничего не выбрать, он продлится сам',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink, height: 1.35),
        ),
      ];
    }
    if (DemoMode.isEnabled.value) {
      return [Text('В демо-режиме выбор тарифа недоступен', style: TextStyle(fontSize: 13, color: p.inkMute))];
    }
    if (_confirm) {
      return [
        Text(
          none
              ? 'Когда закончится текущий тариф, интернет отключится до выбора нового. '
                  'Выбор подтверждается на странице биллинга, она откроется в браузере'
              : 'Тариф «${o.name}» начнёт действовать, когда закончится текущий. '
                  'Выбор подтверждается на странице биллинга, она откроется в браузере',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink, height: 1.35),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton(onPressed: _openBilling, child: const Text('Открыть страницу биллинга')),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: TextButton(onPressed: () => setState(() => _confirm = false), child: const Text('Отмена')),
        ),
      ];
    }
    return [
      SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: () => setState(() => _confirm = true),
          child: Text(none ? 'Остаться без тарифа' : 'Выбрать со следующего периода'),
        ),
      ),
    ];
  }
}
