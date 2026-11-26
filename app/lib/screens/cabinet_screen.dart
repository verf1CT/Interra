import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/auth_store.dart';
import '../services/balance_store.dart';
import '../services/cabinet_parser.dart';
import '../services/charge_reminder.dart';
import '../services/analytics.dart';
import '../services/api_client.dart';
import '../services/quick_actions_service.dart';
import '../services/demo_mode.dart';
import '../widgets/design_system.dart';
import '../widgets/app_sheets.dart';
import '../widgets/motion_kit.dart';
import '../widgets/cabinet_skeleton.dart';
import '../utils/billing_math.dart';
import 'home_tab.dart';
import 'diagnostics_screen.dart';
import 'register_screen.dart';
import 'settings_screen.dart';
import 'payments_history_screen.dart';
import 'services_screen.dart';
import 'premium_tv_screen.dart';
import '../widgets/payment_modal.dart';
import '../widgets/passport_form_sheet.dart';

class CabinetScreen extends StatefulWidget {
  const CabinetScreen({super.key});

  @override
  State<CabinetScreen> createState() => _CabinetScreenState();
}

class _CabinetScreenState extends State<CabinetScreen> with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  CabinetData? _data;
  
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    QuickActionsService.homeRequested.addListener(_refreshFromEvent);
    QuickActionsService.paymentRequested.addListener(_openPayment);
    DemoMode.isEnabled.addListener(_onDemoChanged);
    BalanceStore.restore();
    _refresh();
  }
  
  void _onDemoChanged() {
    if (mounted) _refresh();
  }

  void _refreshFromEvent() {
    setState(() => _currentIndex = 0);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    QuickActionsService.homeRequested.removeListener(_refreshFromEvent);
    QuickActionsService.paymentRequested.removeListener(_openPayment);
    DemoMode.isEnabled.removeListener(_onDemoChanged);
    _payAccounts.dispose();
    _payLoading.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh(silent: true);
    }
  }

  /// идёт обновление при уже показанных данных - по карточке баланса бежит блик
  bool _refreshing = false;

  Future<void> _refresh({bool silent = false}) async {
    if (_data != null && mounted) setState(() => _refreshing = true);
    try {
      await _load(silent: silent);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    if (DemoMode.isEnabled.value) {
      final demo = DemoMode.demoCabinetData;
      await BalanceStore.update(demo.balance, account: demo.account);
      if (mounted) {
        setState(() {
          _data = demo;
          _loading = false;
          _error = null;
        });
      }
      return;
    }

    final token = await AuthStore().appToken;
    if (token == null) {
      _resetToRegister();
      return;
    }

    try {
      // обновление не должно сбрасывать выбранный договор на первый
      final selected = _data != null ? CabinetParser.activeLogin : null;
      CabinetData? data;
      if (selected != null) {
        try {
          data = await CabinetParser.fetchCabinetData(token, targetUrl: selected);
        } catch (e) {
          if (e.toString().contains('auth_expired')) rethrow;
          data = null; // ссылка договора протухла - грузим по умолчанию
        }
        if (data != null) {
          final prev = _data!;
          data = data.copyWith(
            fullName: !CabinetParser.isPlaceholderName(data.fullName)
                ? data.fullName
                : prev.fullName,
            address: data.address.isNotEmpty ? data.address : prev.address,
            accounts: prev.accounts, // на странице договора списка выбора нет
          );
        }
      }
      data ??= await CabinetParser.fetchCabinetData(token);
      if (data == null) throw Exception('data is null');

      await BalanceStore.update(data.balance, account: data.account);
      ChargeReminder.update(data);
      Analytics.cabinetOpened();

      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (e.toString().contains('auth_expired')) {
        await AuthStore().clear();
        _resetToRegister();
        return;
      }
      if (mounted) {
        setState(() {
          if (!silent) _error = 'Не удалось загрузить данные. Проверьте интернет.';
          _loading = false;
        });
      }
    }
  }

  void _resetToRegister() {
    if (DemoMode.isEnabled.value) return;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
      (route) => false,
    );
  }

  Future<void> _openPayment() async {
    final account = _data?.account ?? '';
    await PaymentModal.show(
      context,
      account: account,
      recommendedAmount: _data?.recommendedPayment,
    );
  }

  void _openPassportForm() {
    PassportFormSheet.show(context, onSaved: () => _refresh());
  }

  /// loginUrl договора -> номер для оплаты, подгружается при открытии окна выбора
  final ValueNotifier<Map<String, String>> _payAccounts = ValueNotifier({});

  final ValueNotifier<bool> _payLoading = ValueNotifier(false);

  Future<void> _loadPayAccounts() async {
    if (DemoMode.isEnabled.value) return;
    final token = await AuthStore().appToken;
    if (token == null) return;
    final jobs = <Future<void>>[];
    for (final acc in _data?.accounts ?? const <AccountOption>[]) {
      if (_payAccounts.value.containsKey(acc.loginUrl)) continue;
      jobs.add(CabinetParser.fetchPayAccount(token, acc.loginUrl).then((number) {
        if (!mounted || number.isEmpty) return;
        _payAccounts.value = {..._payAccounts.value, acc.loginUrl: number};
      }));
    }
    if (jobs.isEmpty) return;
    _payLoading.value = true;
    await Future.wait(jobs);
    if (mounted) _payLoading.value = false;
  }

  /// долгое нажатие на чип договора: копирует сырые страницы кабинета в буфер,
  /// чтобы вставить в заметки и отправить разработчику для разбора вёрстки
  Future<void> _copyDebugPages() async {
    final token = await AuthStore().appToken;
    if (token == null || !mounted) return;
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Собираю страницы кабинета...'),
      duration: Duration(seconds: 2),
    ));
    final dump = await CabinetParser.collectDebugDump(token);
    // сначала шлём на наш сервер, оттуда дамп забирает разработчик;
    // сервер недоступен - по-старому в буфер
    if (await ApiClient.sendDebugDump(dump)) {
      messenger.showSnackBar(SnackBar(
        content: Text('Дамп отправлен разработчику, ${(dump.length / 1024).round()} КБ'),
        duration: const Duration(seconds: 4),
      ));
      return;
    }
    await Clipboard.setData(ClipboardData(text: dump));
    messenger.showSnackBar(SnackBar(
      content: Text('Сервер недоступен. Скопировано ${(dump.length / 1024).round()} КБ, вставьте в чат'),
      duration: const Duration(seconds: 5),
    ));
  }

  void _showAccountPicker() {
    if (_data == null || _data!.accounts.isEmpty) return;
    _loadPayAccounts();
    showAppSheet(
      context,
      _AccountPickerBody(
        accounts: _data!.accounts,
        payAccounts: _payAccounts,
        payLoading: _payLoading,
        isCurrent: (acc, number) =>
            (number.isNotEmpty && number == _data!.account) ||
            (number.isEmpty && _data!.fullName == acc.name),
        onSelect: _selectAccount,
      ),
    );
  }

  /// растёт при смене договора: по нему вкладки услуг, ТВ и истории
  /// пересоздаются и грузят данные нового договора, а не первого
  int _selectionEpoch = 0;

  Future<void> _selectAccount(AccountOption acc) async {
    if (DemoMode.isEnabled.value) {
      final demoBalance = acc.accountId == '654321' ? -150.00 : 1250.00;
      BalanceStore.update(demoBalance, account: acc.accountId);
      setState(() {
        _selectionEpoch++;
        _data = CabinetData(
          balance: acc.accountId == '654321' ? -150.00 : 1250.00,
          account: acc.accountId,
          fullName: acc.name,
          tariff: acc.accountId == '654321' ? 'Дачный 50' : 'Комфорт 200',
          address: acc.address,
          login: acc.accountId,
          isRestricted: acc.accountId == '654321',
          recommendedPayment: acc.accountId == '654321' ? '160 ₽' : null,
          accounts: _data!.accounts,
          rawHtml: '',
        );
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final token = await AuthStore().appToken;
      if (token == null) return;
      final newData = await CabinetParser.fetchCabinetData(token, targetUrl: acc.loginUrl);
      if (mounted && newData != null) {
        final account = newData.account.isNotEmpty
            ? newData.account
            : (_payAccounts.value[acc.loginUrl] ?? '');
        await BalanceStore.update(newData.balance, account: account);
        if (!mounted) return;
        setState(() {
          _selectionEpoch++;
          _data = newData.copyWith(
            account: account,
            fullName: !CabinetParser.isPlaceholderName(newData.fullName)
                ? newData.fullName
                : acc.name,
            address: newData.address.isNotEmpty ? newData.address : acc.address,
            accounts: _data!.accounts,
          );
          ChargeReminder.update(_data!);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Switch account error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _appBarTitle {
    switch (_currentIndex) {
      case 0:
        final name = _data == null ? null : firstName(_data!.fullName);
        final hello = greeting(DateTime.now());
        return name == null ? hello : '$hello, $name';
      case 1: return 'Услуги и тарифы';
      case 2: return 'Премиум ТВ';
      case 3: return 'История операций';
      default: return 'Личный кабинет';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle),
        actions: [
          if (_currentIndex != 0) _balanceChip(),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Настройки',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SettingsScreen(),
                settings: const RouteSettings(name: 'settings'),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          ServicesScreen(
            key: ValueKey('services$_selectionEpoch'),
            needsPassport: _data?.needsPassportData ?? false,
            onOpenPassportForm: _openPassportForm,
          ),
          PremiumTvScreen(key: ValueKey('tv$_selectionEpoch')),
          PaymentsHistoryScreen(key: ValueKey('history$_selectionEpoch')),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHomeTab() {
    if (_loading && _data == null) {
      return const CabinetSkeleton();
    }
    if (_error != null && _data == null) {
      return _errorOverlay();
    }
    if (_data == null) return const SizedBox.shrink();
    return HomeTab(
      data: _data!,
      refreshing: _refreshing,
      onRefresh: () => _refresh(silent: true),
      onPay: _openPayment,
      onPickAccount: _showAccountPicker,
      onDumpPages: DemoMode.isEnabled.value ? null : _copyDebugPages,
      onOpenPassport: _openPassportForm,
      onOpenTab: (i) => setState(() => _currentIndex = i),
    );
  }

  Widget _buildBottomNav() {
    return ModernBottomNav(
      currentIndex: _currentIndex,
      onTap: (index) => setState(() => _currentIndex = index),
      items: const [
        ModernNavItem(
          activeIcon: Icons.home_rounded,
          inactiveIcon: Icons.home_outlined,
          label: 'Главная',
        ),
        ModernNavItem(
          activeIcon: Icons.grid_view_rounded,
          inactiveIcon: Icons.grid_view_outlined,
          label: 'Услуги',
        ),
        ModernNavItem(
          activeIcon: Icons.tv_rounded,
          inactiveIcon: Icons.tv_outlined,
          label: 'ТВ',
        ),
        ModernNavItem(
          activeIcon: Icons.receipt_long_rounded,
          inactiveIcon: Icons.receipt_long_outlined,
          label: 'История',
        ),
      ],
    );
  }

  Widget _balanceChip() => ValueListenableBuilder<BalanceInfo?>(
        valueListenable: BalanceStore.notifier,
        builder: (context, info, _) {
          if (info == null) return const SizedBox.shrink();
          final negative = info.amount < 0;
          final dark = Theme.of(context).brightness == Brightness.dark;
          final color = negative
              ? AppColors.danger
              : (dark ? AppColors.brand : AppColors.brandInk);
          return Center(
            child: GestureDetector(
              onTap: _openPayment,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet_rounded, size: 15, color: color),
                    const SizedBox(width: 6),
                    Text(
                      BalanceStore.format(info.amount),
                      style: TextStyle(
                        color: color,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _errorOverlay() => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.brand, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.p.ink, fontSize: 15, height: 1.4, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _refresh(),
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Повторить'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const DiagnosticsScreen(),
              )),
              child: const Text('Диагностика сети'),
            ),
          ],
        ),
      );
}


/// содержимое шторки выбора договора: фио, под ним номер счёта, ниже адрес
class _AccountPickerBody extends StatefulWidget {
  final List<AccountOption> accounts;
  final ValueNotifier<Map<String, String>> payAccounts;
  final ValueNotifier<bool> payLoading;
  final bool Function(AccountOption acc, String number) isCurrent;
  final Future<void> Function(AccountOption acc) onSelect;

  const _AccountPickerBody({
    required this.accounts,
    required this.payAccounts,
    required this.payLoading,
    required this.isCurrent,
    required this.onSelect,
  });

  @override
  State<_AccountPickerBody> createState() => _AccountPickerBodyState();
}

class _AccountPickerBodyState extends State<_AccountPickerBody> {
  String? _busy;

  Future<void> _tap(AccountOption acc) async {
    if (_busy != null) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = acc.loginUrl);
    await widget.onSelect(acc);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Выберите договор',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: context.p.ink,
          ),
        ),
        const SizedBox(height: 14),
        Flexible(
          child: SingleChildScrollView(
            child: ValueListenableBuilder<Map<String, String>>(
              valueListenable: widget.payAccounts,
              builder: (_, payAccounts, __) => ValueListenableBuilder<bool>(
                valueListenable: widget.payLoading,
                builder: (_, loading, __) => Column(
                  children: [
                    for (final acc in widget.accounts) ...[
                      Builder(builder: (_) {
                        final number = payAccounts[acc.loginUrl] ??
                            (DemoMode.isEnabled.value ? acc.accountId : '');
                        return _AccountRow(
                          account: acc,
                          number: number,
                          numberLoading: loading && number.isEmpty,
                          current: widget.isCurrent(acc, number),
                          busy: _busy == acc.loginUrl,
                          onTap: () => _tap(acc),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  final AccountOption account;
  final String number;
  final bool numberLoading;
  final bool current;
  final bool busy;
  final VoidCallback onTap;

  const _AccountRow({
    required this.account,
    required this.number,
    required this.numberLoading,
    required this.current,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Pressable(
      onTap: current ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: current ? AppColors.brand.withValues(alpha: 0.08) : p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: current ? AppColors.brand : p.line,
            width: current ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: current ? FontWeight.w800 : FontWeight.w700,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (number.isNotEmpty)
                    Text(
                      'Л/С $number',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: p.ink.withValues(alpha: 0.75),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    )
                  else if (numberLoading)
                    Container(
                      width: 96,
                      height: 12,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: p.line,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  if (account.address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      account.address,
                      style: TextStyle(fontSize: 12.5, color: p.inkMute),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.brand),
              )
            else if (current)
              const Icon(Icons.check_circle_rounded, color: AppColors.brand, size: 22),
          ],
        ),
      ),
    );
  }
}
