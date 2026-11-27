import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_store.dart';
import '../services/balance_store.dart';
import '../services/cabinet_parser.dart';
import '../services/demo_mode.dart';
import '../theme.dart';
import '../utils/billing_math.dart';
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
    final c = _catalog!;
    final current = group.isNoTariff ? c.current == null : offer.name == c.current;
    showAppSheet<void>(
      context,
      _OfferSheet(
        offer: offer,
        group: group,
        current: current,
        chosen: c.next != null && offer.name == c.next && !current,
        changeOrdered: c.next != null && c.next != (c.current ?? 'Нет тарифа'),
        // биллинг принял заказ: отмечаем у себя, страница договора обновится позже
        onOrdered: () => setState(() => _catalog = c.withNext(current ? null : offer.name)),
      ),
    );
  }

  /// подпись под тарифом: действует сейчас или выбран на следующий период
  String? _badge(TariffCatalog c, TariffOffer o, {bool none = false}) {
    final current = none ? c.current == null : o.name == c.current;
    if (current) return 'Действует сейчас';
    if (c.next != null && o.name == c.next) return 'Выбран со следующего периода';
    return null;
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
                _OfferRow(offer: o, badge: _badge(c, o), onTap: () => _open(o, g)),
              ],
            ]),
            const SizedBox(height: 18),
          ],
          for (final g in none) ...[
            PillGroupCard(children: [
              _OfferRow(
                offer: c.offers[g.id]!.first,
                badge: _badge(c, c.offers[g.id]!.first, none: true),
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
  final String? badge;
  final String? note;
  final VoidCallback onTap;

  const _OfferRow({required this.offer, this.badge, this.note, required this.onTap});

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
                    if (badge != null) ...[
                      const SizedBox(height: 2),
                      Text(badge!,
                          style: const TextStyle(
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

enum _Step { details, loading, confirm, sending, done, failed }

/// шторка тарифа: цена и описание биллинга. выбор в два шага, как на сайте:
/// открываем страницу подтверждения (там дата смены), затем жмём «ДА»
class _OfferSheet extends StatefulWidget {
  final TariffOffer offer;
  final TariffGroup group;
  final bool current;

  /// этот тариф уже заказан на следующий период
  final bool chosen;

  /// заказана смена на другой тариф: тогда действующий можно вернуть
  final bool changeOrdered;
  final VoidCallback onOrdered;

  const _OfferSheet({
    required this.offer,
    required this.group,
    required this.current,
    this.chosen = false,
    this.changeOrdered = false,
    required this.onOrdered,
  });

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  _Step _step = _Step.details;
  TariffOrderPage? _page;
  bool _ok = false;

  Future<void> _prepare() async {
    setState(() => _step = _Step.loading);
    TariffOrderPage? page;
    try {
      final token = await AuthStore().appToken;
      if (token != null) page = await CabinetParser.fetchTariffOrder(token, widget.offer);
    } catch (e) {
      debugPrint('страница подтверждения тарифа: $e');
    }
    if (!mounted) return;
    setState(() {
      _page = page;
      _step = page != null && page.canOrder ? _Step.confirm : _Step.failed;
    });
  }

  Future<void> _order() async {
    setState(() => _step = _Step.sending);
    var ok = false;
    try {
      final token = await AuthStore().appToken;
      if (token != null) ok = await CabinetParser.orderTariff(token, widget.offer, _page!);
    } catch (e) {
      debugPrint('заказ тарифа: $e');
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (ok) widget.onOrdered();
    setState(() {
      _ok = ok;
      _step = _Step.done;
    });
  }

  Future<void> _openBilling() async {
    final url = CabinetParser.tariffWebUrl(widget.offer);
    Navigator.of(context).pop();
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('не открылась страница тарифа: $e');
    }
  }

  String get _when {
    final d = _page?.switchAt;
    return d == null ? 'после окончания текущего тарифа' : 'с ${shortDate(d)}';
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

  Widget _message(String text, {IconData? icon, Color? color}) {
    final p = context.p;
    final t = Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink, height: 1.35));
    if (icon == null) return t;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(child: t),
      ],
    );
  }

  List<Widget> _actions() {
    final p = context.p;
    final o = widget.offer;
    final none = widget.group.isNoTariff;
    final keep = widget.current && widget.changeOrdered;
    if (widget.chosen && _step == _Step.details) {
      return [_message('Этот тариф уже выбран, он начнёт действовать после окончания текущего')];
    }
    if (widget.current && !keep) {
      return [_message(none ? 'Сейчас тарифа нет' : 'Это ваш тариф. Если ничего не выбрать, он продлится сам')];
    }
    if (DemoMode.isEnabled.value) {
      return [Text('В демо-режиме выбор тарифа недоступен', style: TextStyle(fontSize: 13, color: p.inkMute))];
    }
    switch (_step) {
      case _Step.loading:
      case _Step.sending:
        return const [
          SizedBox(height: 52, child: Center(child: CircularProgressIndicator(color: AppColors.brand))),
        ];
      case _Step.confirm:
        return [
          _message(keep
              ? 'Заказанная смена отменится, «${o.name}» останется и после окончания текущего периода. Оставить?'
              : none
                  ? 'Тариф закончится $_when, после этого интернет отключится, а абонплата сниматься не будет. Продолжить?'
                  : 'Тариф сменится на «${o.name}» $_when. Сменить?'),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _order,
              child: Text(keep ? 'Да, оставить' : none ? 'Да, остаться без тарифа' : 'Да, сменить'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: TextButton(onPressed: () => setState(() => _step = _Step.details), child: const Text('Отмена')),
          ),
        ];
      case _Step.done:
        return [
          _ok
              ? _message(keep
                      ? 'Готово, «${o.name}» останется'
                      : none
                          ? 'Готово, $_when тарифа не будет'
                          : 'Готово, $_when будет «${o.name}»',
                  icon: Icons.check_circle_rounded, color: AppColors.ok)
              : _message('Биллинг не подтвердил смену тарифа. Попробуйте позже или выберите на сайте',
                  icon: Icons.info_outline_rounded, color: AppColors.danger),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: _ok
                ? OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Готово'))
                : OutlinedButton(onPressed: _openBilling, child: const Text('Открыть на сайте')),
          ),
        ];
      case _Step.failed:
        return [
          _message('Не удалось открыть подтверждение в биллинге', icon: Icons.info_outline_rounded, color: AppColors.danger),
          const SizedBox(height: 14),
          SizedBox(height: 48, child: FilledButton(onPressed: _prepare, child: const Text('Повторить'))),
          const SizedBox(height: 8),
          SizedBox(height: 48, child: TextButton(onPressed: _openBilling, child: const Text('Открыть на сайте'))),
        ];
      case _Step.details:
        return [
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _prepare,
              child: Text(keep ? 'Оставить этот тариф' : none ? 'Остаться без тарифа' : 'Выбрать со следующего периода'),
            ),
          ),
        ];
    }
  }
}
