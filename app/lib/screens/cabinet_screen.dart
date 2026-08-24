import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../theme.dart';
import '../services/auth_store.dart';
import '../services/balance_store.dart';
import '../services/cabinet_parser.dart';
import '../services/analytics.dart';
import '../services/quick_actions_service.dart';
import 'diagnostics_screen.dart';
import 'register_screen.dart';
import 'settings_screen.dart';
import 'payments_history_screen.dart';
import 'services_screen.dart';

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
    BalanceStore.restore();
    _refresh();
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh(silent: true);
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
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
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
      (route) => false,
    );
  }

  Future<void> _openPayment() async {
    final url = Uri.parse(AppConfig.portalUrl); 
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Не удалось открыть оплату: $e');
    }
  }

  String get _appBarTitle {
    switch (_currentIndex) {
      case 0: return 'Личный кабинет';
      case 1: return 'История платежей';
      case 2: return 'Услуги и тарифы';
      default: return 'Личный кабинет';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle),
        actions: [
          _balanceChip(),
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
          const PaymentsHistoryScreen(),
          const ServicesScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHomeTab() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.brand));
    }
    if (_error != null && _data == null) {
      return _errorOverlay();
    }
    
    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: () => _refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_data != null) ...[
            _buildInfoCard(),
            const SizedBox(height: 24),
            _buildActionButtons(),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: context.p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.p.line),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Абонент',
            style: TextStyle(fontSize: 13, color: context.p.inkMute, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _data!.fullName,
            style: TextStyle(fontSize: 18, color: context.p.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Лицевой счёт',
                    style: TextStyle(fontSize: 13, color: context.p.inkMute, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _data!.account,
                    style: TextStyle(fontSize: 16, color: context.p.ink, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Тариф',
                    style: TextStyle(fontSize: 13, color: context.p.inkMute, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _data!.tariff,
                    style: TextStyle(fontSize: 16, color: context.p.ink, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _openPayment,
            icon: const Icon(Icons.payment),
            label: const Text('Пополнить'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) {
        HapticFeedback.selectionClick();
        setState(() => _currentIndex = index);
      },
      selectedItemColor: AppColors.brand,
      unselectedItemColor: context.p.inkMute,
      backgroundColor: context.p.card,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_rounded),
          label: 'Главная',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.history_rounded),
          label: 'История',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.miscellaneous_services_rounded),
          label: 'Услуги',
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
