import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/auth_store.dart';
import '../services/balance_store.dart';
import '../services/cabinet_parser.dart';
import '../services/analytics.dart';
import '../services/quick_actions_service.dart';
import '../services/demo_mode.dart';
import '../widgets/design_system.dart';
import 'support_screen.dart';
import 'diagnostics_screen.dart';
import 'register_screen.dart';
import 'settings_screen.dart';
import 'payments_history_screen.dart';
import 'services_screen.dart';
import 'premium_tv_screen.dart';
import 'lan_devices_screen.dart';
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (_data != null) ...[
            _buildHeroBalanceCard(),
            const SizedBox(height: 14),
            _buildBentoSection(),
            const SizedBox(height: 14),
            _buildServiceQuickRow(),
            if (!DemoMode.isEnabled.value && _data!.needsPassportData) ...[
              const SizedBox(height: 14),
              _buildPassportNotice(),
            ],
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroBalanceCard() {
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
      decoration: cardBox(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_data!.accounts.length > 1)
                InkWell(
                  onTap: _showAccountPicker,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.brand.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.swap_horiz_rounded, size: 15, color: AppColors.brand),
                        const SizedBox(width: 5),
                        Text(
                          'Сменить договор (${_data!.accounts.length})',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brand,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.brand),
                      ],
                    ),
                  ),
                )
              else
                MorphingCopyBadge(
                  textToCopy: _data!.account,
                  displayLabel: 'Договор № $displayAccount',
                ),
              PulseDot(
                color: statusColor,
                label: statusText,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Текущий баланс',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: context.p.inkMute,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              NumberTicker(
                value: _data!.balance,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: isRestricted ? const Color(0xFFEF4444) : context.p.ink,
                ),
              ),
            ],
          ),
          if (isRestricted) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _data!.recommendedPayment != null
                          ? 'Услуги ограничены. Сумма для включения: ${_data!.recommendedPayment}'
                          : 'Услуги ограничены. Пополните баланс для продолжения',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.p.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.wifi_rounded, size: 15, color: AppColors.brand),
                const SizedBox(width: 5),
                Text(
                  displayTariff,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.p.ink),
                ),
                if (_data!.address.isNotEmpty) ...[
                  Text(' • ', style: TextStyle(color: context.p.inkMute)),
                  Expanded(
                    child: Text(
                      _data!.address,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: context.p.inkMute),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openPayment,
            icon: const Icon(Icons.payment_rounded, size: 18),
            label: Text(
              isRestricted && _data!.recommendedPayment != null
                  ? 'Оплатить ${_data!.recommendedPayment} и включить'
                  : 'Пополнить баланс',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBentoSection() {
    final hasTariff = _data!.tariff.isNotEmpty &&
        _data!.tariff != 'Нет тарифа' &&
        _data!.tariff != 'Неизвестный тариф';
    final displayTariff = hasTariff ? _data!.tariff : 'До 200 Мбит/с';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 11,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: cardBox(context, radius: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.speed_rounded, size: 18, color: AppColors.brand),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '2 мс',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Сеть и скорость',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.p.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  'Шлюз Interra в норме',
                  style: TextStyle(fontSize: 11.5, color: context.p.inkMute),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.p.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: context.p.inkMute),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          displayTariff,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.p.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Тест сети',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 13, color: AppColors.brand),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 10,
          child: Column(
            children: [
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SupportScreen()),
                ),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: cardBox(context, radius: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.forum_rounded, size: 16, color: AppColors.accent),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'онлайн',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Поддержка',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.p.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Чат 24/7 с ботом',
                        style: TextStyle(fontSize: 11, color: context.p.inkMute),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => _currentIndex = 2),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: cardBox(context, radius: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.tv_rounded, size: 16, color: Color(0xFF8B5CF6)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Full HD',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF8B5CF6)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Интерра ТВ',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.p.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '150+ каналов',
                        style: TextStyle(fontSize: 11, color: context.p.inkMute),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServiceQuickRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: cardBox(context, radius: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _bentoQuickAction(
            icon: Icons.devices_rounded,
            label: 'Устройства сети',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LanDevicesScreen()),
            ),
          ),
          Container(width: 1, height: 28, color: context.p.line),
          _bentoQuickAction(
            icon: Icons.receipt_long_rounded,
            label: 'История платежей',
            onTap: () => setState(() => _currentIndex = 3),
          ),
          Container(width: 1, height: 28, color: context.p.line),
          _bentoQuickAction(
            icon: Icons.tune_rounded,
            label: 'Все тарифы',
            onTap: () => setState(() => _currentIndex = 1),
          ),
        ],
      ),
    );
  }

  Widget _bentoQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: AppColors.brand),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.p.ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassportNotice() {
    return InkWell(
      onTap: _openPassportForm,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.brand.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.brand.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.assignment_ind_outlined, size: 18, color: AppColors.brand),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Требуются данные паспорта для договора. Заполнить',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.p.ink),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.brand),
          ],
        ),
      ),
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
