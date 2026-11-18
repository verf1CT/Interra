import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/auth_store.dart';
import '../services/balance_store.dart';
import '../services/cabinet_parser.dart';
import '../services/analytics.dart';
import '../services/quick_actions_service.dart';
import '../services/demo_mode.dart';
import 'support_screen.dart';
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

  Future<void> _refresh({bool silent = false}) async {
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
      case 0: return 'Личный кабинет';
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
            const SizedBox(height: 16),
            _buildActionButtons(),
            const SizedBox(height: 16),
            _buildPromoCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final displayName = (_data!.fullName.isNotEmpty && _data!.fullName != 'Абонент')
        ? _data!.fullName
        : (_data!.account.isNotEmpty ? 'Договор № ${_data!.account}' : 'Абонент');
    final displayAccount = (_data!.account.isNotEmpty && _data!.account != '—') ? _data!.account : '—';
    final hasTariff = _data!.tariff.isNotEmpty &&
        _data!.tariff != 'Нет тарифа' &&
        _data!.tariff != 'Неизвестный тариф';
    final displayTariff = hasTariff ? _data!.tariff : 'Нет тарифа';

    final bool isRestricted = _data!.isRestricted || _data!.balance < 0;
    final Color statusColor = isRestricted ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    final String statusText = isRestricted ? 'Ограничен' : 'Активен';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardBox(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Абонент',
                      style: TextStyle(fontSize: 13, color: context.p.inkMute, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayName,
                      style: TextStyle(fontSize: 18, color: context.p.ink, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 7, color: statusColor),
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_data!.address.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 15, color: context.p.inkMute),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _data!.address,
                    style: TextStyle(fontSize: 13, color: context.p.inkMute, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
          if (_data!.accounts.length > 1) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: _showAccountPicker,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.brand.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_horiz_rounded, size: 16, color: AppColors.brand),
                    const SizedBox(width: 6),
                    Text(
                      'Сменить договор (${_data!.accounts.length})',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.brand),
                  ],
                ),
              ),
            ),
          ],
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
                  Row(
                    children: [
                      Text(
                        displayAccount,
                        style: TextStyle(fontSize: 16, color: context.p.ink, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          if (_data!.account.isNotEmpty && _data!.account != '—') {
                            Clipboard.setData(ClipboardData(text: _data!.account));
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Лицевой счёт ${_data!.account} скопирован'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        child: Icon(Icons.copy_rounded, size: 16, color: context.p.inkMute),
                      ),
                    ],
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
                    displayTariff,
                    style: TextStyle(
                      fontSize: 16,
                      color: hasTariff ? context.p.ink : context.p.inkMute,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (isRestricted) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Услуги связи ограничены',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                        if (_data!.recommendedPayment != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Рекомендуемая сумма для включения: ${_data!.recommendedPayment}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: context.p.ink,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!DemoMode.isEnabled.value && _data!.needsPassportData) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: _openPassportForm,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.assignment_ind_outlined, size: 18, color: AppColors.brand),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Требуются данные для тарифа. Заполнить',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brand),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: AppColors.brand),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: context.p.card,
                shape: BoxShape.circle,
                border: Border.all(color: context.p.line),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: AppColors.brand, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.p.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F70B7), Color(0xFF1990E6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F70B7).withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Интерра ТВ онлайн',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '150+ телеканалов в Full HD на смартфоне, планшете и ТВ',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white70,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => setState(() => _currentIndex = 2),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F70B7),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Смотреть ТВ', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.tv_rounded, color: Colors.white, size: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _openPayment,
          icon: const Icon(Icons.payment_rounded, size: 20),
          label: const Text('Пополнить баланс', style: TextStyle(fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _quickActionItem(
              icon: Icons.headset_mic_rounded,
              label: 'Поддержка',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SupportScreen()),
              ),
            ),
            _quickActionItem(
              icon: Icons.speed_rounded,
              label: 'Скорость',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
              ),
            ),
            _quickActionItem(
              icon: Icons.tv_rounded,
              label: 'Интерра ТВ',
              onTap: () => setState(() => _currentIndex = 2),
            ),
            _quickActionItem(
              icon: Icons.receipt_long_rounded,
              label: 'История',
              onTap: () => setState(() => _currentIndex = 3),
            ),
          ],
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
          icon: Icon(Icons.miscellaneous_services_rounded),
          label: 'Услуги',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.tv_rounded),
          label: 'Премиум ТВ',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.history_rounded),
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
