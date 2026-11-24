import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/auth_store.dart';
import '../services/balance_store.dart';
import '../services/cabinet_parser.dart';
import '../services/analytics.dart';
import '../services/quick_actions_service.dart';
import '../services/demo_mode.dart';
import '../widgets/design_system.dart';
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
      final data = await CabinetParser.fetchCabinetData(token);
      if (data == null) throw Exception('data is null');

      await BalanceStore.update(data.balance, account: data.account);
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

  void _showAccountPicker() {
    if (_data == null || _data!.accounts.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: context.p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Выберите договор',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.p.ink,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final acc in _data!.accounts) ...[
                Builder(
                  builder: (_) {
                    final isCurrent = (_data!.account.isNotEmpty && acc.accountId == _data!.account) ||
                        (_data!.fullName == acc.name);
                    return Card(
                      elevation: 0,
                      color: isCurrent
                          ? AppColors.brand.withValues(alpha: 0.08)
                          : context.p.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isCurrent ? AppColors.brand : context.p.line,
                          width: isCurrent ? 1.5 : 1,
                        ),
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.account_circle_outlined,
                          color: isCurrent ? AppColors.brand : context.p.inkMute,
                        ),
                        title: Text(
                          acc.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                            color: context.p.ink,
                          ),
                        ),
                        subtitle: acc.address.isNotEmpty
                            ? Text(
                                acc.address,
                                style: TextStyle(fontSize: 12.5, color: context.p.inkMute),
                              )
                            : (acc.accountId.isNotEmpty ? Text('Л/С: ${acc.accountId}') : null),
                        trailing: isCurrent
                            ? const Icon(Icons.check_circle_rounded, color: AppColors.brand)
                            : null,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (!isCurrent) {
                            _selectAccount(acc);
                          }
                        },
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectAccount(AccountOption acc) async {
    if (DemoMode.isEnabled.value) {
      setState(() {
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
        setState(() {
          _data = CabinetData(
            balance: newData.balance,
            account: newData.account.isNotEmpty ? newData.account : acc.accountId,
            fullName: newData.fullName != 'Абонент' ? newData.fullName : acc.name,
            tariff: newData.tariff,
            address: newData.address.isNotEmpty ? newData.address : acc.address,
            login: newData.login,
            needsPassportData: newData.needsPassportData,
            isRestricted: newData.isRestricted,
            recommendedPayment: newData.recommendedPayment,
            accounts: _data!.accounts,
            rawHtml: newData.rawHtml,
          );
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
          ServicesScreen(onOpenPassportForm: _openPassportForm),
          const PremiumTvScreen(),
          const PaymentsHistoryScreen(),
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
