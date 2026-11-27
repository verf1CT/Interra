import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_store.dart';
import '../services/cabinet_parser.dart';
import '../services/demo_mode.dart';
import '../theme.dart';
import '../services/balance_store.dart';
import '../widgets/app_sheets.dart';
import '../widgets/design_system.dart';
import '../widgets/motion_kit.dart';

/// вкладка «ТВ»: вход в Смотрёшку и пакеты Premium TV и IPTV с ценами -
/// всё со страниц кабинета выбранного договора. пакет открывается шторкой,
/// подключение - через форму биллинга с подтверждением суммы
class PremiumTvScreen extends StatefulWidget {
  const PremiumTvScreen({super.key});

  @override
  State<PremiumTvScreen> createState() => _PremiumTvScreenState();
}

class _PremiumTvScreenState extends State<PremiumTvScreen> {
  bool _loading = true;
  bool _failed = false;
  TvInfo? _tv;

  @override
  void initState() {
    super.initState();
    DemoMode.isEnabled.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DemoMode.isEnabled.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    TvInfo? tv;
    if (DemoMode.isEnabled.value) {
      tv = DemoMode.demoTv;
    } else {
      try {
        final token = await AuthStore().appToken;
        if (token != null) tv = await CabinetParser.fetchTv(token);
      } catch (e) {
        debugPrint('тв не загрузилось: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _tv = tv;
      _failed = tv == null;
      _loading = false;
    });
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Не удалось открыть $url: $e');
    }
  }

  /// шторка пакета: цена, каналы и подключение с подтверждением
  void _openPackage(String script, TvPackage pkg) {
    showAppSheet<void>(context, _PackageSheet(script: script, pkg: pkg));
  }

  void _openStore() {
    // точных ссылок на карточку приложения у нас нет - открываем поиск магазина
    const q = 'Смотрёшка';
    _open(Platform.isIOS
        ? 'itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=${Uri.encodeComponent(q)}'
        : 'market://search?q=${Uri.encodeComponent(q)}');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _skeleton();
    final tv = _tv;
    if (_failed || tv == null || tv.isEmpty) {
      return _ErrorState(onRetry: _load);
    }

    var i = 0;
    final premiumBase = tv.premium.where((e) => !e.extra).toList();
    final premiumExtra = tv.premium.where((e) => e.extra).toList();

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (tv.login != null) ...[
            StaggerIn(
              index: i++,
              child: _LoginCard(login: tv.login!, password: tv.password, onStore: _openStore),
            ),
            const SizedBox(height: 22),
          ],
          if (premiumBase.isNotEmpty) ...[
            const PillSectionHeader('Premium TV · основные пакеты'),
            StaggerIn(index: i++, child: _packages(premiumBase, 'aaaxtvpsm')),
            const SizedBox(height: 18),
          ],
          if (premiumExtra.isNotEmpty) ...[
            const PillSectionHeader('Premium TV · дополнительные'),
            StaggerIn(index: i++, child: _packages(premiumExtra, 'aaaxtvpsm')),
            const SizedBox(height: 6),
            _hint('Заказываются к основному пакету'),
            const SizedBox(height: 18),
          ],
          if (tv.iptvFreeBase || tv.iptv.isNotEmpty) ...[
            const PillSectionHeader('IPTV'),
            StaggerIn(
              index: i++,
              child: PillGroupCard(children: [
                if (tv.iptvFreeBase)
                  const PillTile(
                    icon: Icons.check_circle_rounded,
                    iconColor: AppColors.ok,
                    title: 'Базовый пакет',
                    subtitle: 'Подключён всем абонентам бесплатно',
                  ),
                for (final pkg in tv.iptv) ...[
                  if (tv.iptvFreeBase || pkg != tv.iptv.first) const PillDivider(),
                  _packageTile(pkg, 'aaaiptv'),
                ],
              ]),
            ),
            const SizedBox(height: 6),
            _hint('На Smart TV смотреть можно без приставки'),
          ],
        ],
      ),
    );
  }

  Widget _packages(List<TvPackage> list, String script) => PillGroupCard(children: [
        for (var k = 0; k < list.length; k++) ...[
          if (k > 0) const PillDivider(),
          _packageTile(list[k], script),
        ],
      ]);

  Widget _packageTile(TvPackage pkg, String script) {
    final p = context.p;
    return PillTile(
      icon: Icons.live_tv_rounded,
      iconColor: AppColors.brand,
      title: pkg.name,
      subtitle: pkg.note,
      onTap: () => _openPackage(script, pkg),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pkg.price != null)
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '${pkg.price} ₽',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: p.ink),
                ),
                TextSpan(
                  text: ' /мес',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.inkMute),
                ),
              ]),
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
            ),
          Icon(Icons.chevron_right_rounded, size: 20, color: p.inkFaint),
        ],
      ),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(text, style: TextStyle(fontSize: 12.5, color: context.p.inkFaint)),
      );

  Widget _skeleton() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: const [
          SkeletonBox(width: double.infinity, height: 168, radius: 22),
          SizedBox(height: 22),
          SkeletonBox(width: 180, height: 14),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 200, radius: 22),
        ],
      );
}

/// логин и пароль для Смотрёшки: абоненты их теряют, поэтому крупно и с копированием
class _LoginCard extends StatefulWidget {
  final String login;
  final String? password;
  final VoidCallback onStore;

  const _LoginCard({required this.login, this.password, required this.onStore});

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final pass = widget.password;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: cardBox(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Вход в Смотрёшку',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink)),
          const SizedBox(height: 4),
          Text('Вводится один раз в приложении на телефоне, планшете или приставке',
              style: TextStyle(fontSize: 12.5, color: p.inkMute, height: 1.35)),
          const SizedBox(height: 14),
          _CredentialRow(label: 'Логин', value: widget.login, shown: widget.login),
          if (pass != null) ...[
            const SizedBox(height: 8),
            _CredentialRow(
              label: 'Пароль',
              value: pass,
              shown: _showPassword ? pass : '•' * pass.length,
              extra: IconButton(
                tooltip: _showPassword ? 'Скрыть пароль' : 'Показать пароль',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 52),
                padding: EdgeInsets.zero,
                // иконку жмём к соседней кнопке копирования, зона нажатия остаётся 44
                style: IconButton.styleFrom(alignment: Alignment.centerRight),
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: p.inkMute,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: widget.onStore,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Скачать Смотрёшку'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CredentialRow extends StatefulWidget {
  final String label;
  final String value;
  final String shown;
  final Widget? extra;

  const _CredentialRow({required this.label, required this.value, required this.shown, this.extra});

  @override
  State<_CredentialRow> createState() => _CredentialRowState();
}

class _CredentialRowState extends State<_CredentialRow> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.value));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label, style: TextStyle(fontSize: 11.5, color: p.inkMute)),
                const SizedBox(height: 2),
                Text(
                  widget.shown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (widget.extra != null) widget.extra!,
          IconButton(
            tooltip: 'Скопировать',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 52),
            padding: EdgeInsets.zero,
            onPressed: _copy,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                key: ValueKey(_copied),
                size: 19,
                color: _copied ? AppColors.ok : p.inkMute,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.live_tv_rounded, size: 36, color: p.inkFaint),
            const SizedBox(height: 12),
            Text('Не удалось загрузить ТВ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.ink)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

enum _SheetStep { loading, failed, details, confirm, sending, done }

/// шторка пакета. подключение платное, поэтому в два шага: «Подключить» ->
/// подтверждение с суммой списания -> запрос в биллинг -> перечитываем пакет
class _PackageSheet extends StatefulWidget {
  final String script;
  final TvPackage pkg;
  const _PackageSheet({required this.script, required this.pkg});

  @override
  State<_PackageSheet> createState() => _PackageSheetState();
}

class _PackageSheetState extends State<_PackageSheet> {
  _SheetStep _step = _SheetStep.loading;
  TvPackageDetails? _d;
  String? _result;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _step = _SheetStep.loading);
    TvPackageDetails? d;
    if (DemoMode.isEnabled.value || widget.pkg.href.isEmpty) {
      d = TvPackageDetails(
        name: widget.pkg.name,
        price: widget.pkg.price?.toDouble(),
        period: 'месяц',
        note: widget.pkg.note,
      );
    } else {
      try {
        final token = await AuthStore().appToken;
        if (token != null) d = await CabinetParser.fetchTvPackage(token, widget.script, widget.pkg.href);
      } catch (e) {
        debugPrint('пакет не загрузился: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _d = d;
      _step = d == null ? _SheetStep.failed : _SheetStep.details;
    });
  }

  Future<void> _enable() async {
    final before = _d!;
    setState(() => _step = _SheetStep.sending);
    TvPackageDetails? after;
    try {
      final token = await AuthStore().appToken;
      if (token != null) {
        after = await CabinetParser.enableTvPackage(token, widget.script, widget.pkg.href, before);
      }
    } catch (e) {
      debugPrint('пакет не подключился: $e');
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      // успех - только если биллинг убрал кнопку «включить»
      _ok = after != null && !after.canEnable;
      if (after != null) _d = after;
      final status = after?.status ?? '';
      _result = _ok
          ? (status.isNotEmpty ? 'Пакет подключён. $status' : 'Пакет подключён')
          : 'Биллинг не подтвердил подключение. Проверьте баланс или попробуйте позже';
      _step = _SheetStep.done;
    });
  }

  String _price(TvPackageDetails d) {
    if (d.price == null) return '';
    final sum = BalanceStore.format(d.price!);
    return d.period == null ? sum : '$sum за ${d.period}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final d = _d;
    if (_step == _SheetStep.loading) {
      return const SizedBox(
        height: 140,
        child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }
    if (_step == _SheetStep.failed || d == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Не удалось открыть пакет',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.ink)),
          const SizedBox(height: 16),
          SizedBox(height: 48, child: FilledButton(onPressed: _load, child: const Text('Повторить'))),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(d.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.ink)),
        if (d.price != null) ...[
          const SizedBox(height: 4),
          Text(_price(d),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.inkMute,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
        if (d.note != null) ...[
          const SizedBox(height: 10),
          Text(d.note!, style: TextStyle(fontSize: 13.5, color: p.ink, height: 1.35)),
        ],
        if (d.channels.isNotEmpty || d.channelCount != null) ...[
          const SizedBox(height: 14),
          Text(
            d.channelCount != null ? 'Каналы · ${d.channelCount}' : 'Каналы',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.inkMute),
          ),
          if (d.channels.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in d.channels)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: p.surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(c,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 18),
        ..._actions(d),
      ],
    );
  }

  List<Widget> _actions(TvPackageDetails d) {
    final p = context.p;
    switch (_step) {
      case _SheetStep.confirm:
        final period = d.period != null ? ' за ${d.period}' : '';
        return [
          Text(
            d.price != null
                ? 'С баланса спишется ${BalanceStore.format(d.price!)}$period. Подключить?'
                : 'Пакет платный, сумму спишет биллинг. Подключить?',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink, height: 1.35),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 52, child: FilledButton(onPressed: _enable, child: const Text('Да, подключить'))),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: () => setState(() => _step = _SheetStep.details),
              child: const Text('Отмена'),
            ),
          ),
        ];
      case _SheetStep.sending:
        return const [
          SizedBox(height: 52, child: Center(child: CircularProgressIndicator(color: AppColors.brand))),
        ];
      case _SheetStep.done:
        return [
          Row(
            children: [
              Icon(_ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  color: _ok ? AppColors.ok : AppColors.danger, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_result ?? '',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink, height: 1.35)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Готово')),
          ),
        ];
      default:
        if (DemoMode.isEnabled.value) {
          return [Text('В демо-режиме подключение недоступно', style: TextStyle(fontSize: 13, color: p.inkMute))];
        }
        if (!d.canEnable) {
          return [
            Text(d.status.isNotEmpty ? d.status : 'Подключить этот пакет сейчас нельзя',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink)),
          ];
        }
        return [
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: () => setState(() => _step = _SheetStep.confirm),
              child: Text(d.price != null ? 'Подключить за ${BalanceStore.format(d.price!)}' : 'Подключить'),
            ),
          ),
        ];
    }
  }
}
