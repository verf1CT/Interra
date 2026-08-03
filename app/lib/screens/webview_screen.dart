import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config.dart';
import '../theme.dart';
import '../services/cabinet_interop.dart';
import '../services/cabinet_navigation.dart';
import '../services/auth_store.dart';
import '../services/billing_api.dart';
import '../services/analytics.dart';
import '../services/balance_store.dart';
import '../services/page_cache.dart';
import '../services/quick_actions_service.dart';
import '../widgets/cabinet_skeleton.dart';
import 'diagnostics_screen.dart';
import 'register_screen.dart';
import 'settings_screen.dart';

/// главный экран - WebView с веб-кабинетом Интерра.
///
/// Схема `bbb`: при каждом открытии берём свежую ссылку на ЛК через
/// `cmd=open&app={token}` и грузим страницу «Основная информация». ссылка
/// живёт ~30 минут, поэтому при возврате из фона и протухшей сессии ссылку
/// перезапрашиваем автоматически
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _loading = true;
  bool _firstLoaded = false;
  String? _error;
  bool _offline = false; // показываем кэш-снимок без сети
  String? _liveUrl; // URL последней «живой» (сетевой) загрузки - для кэша
  DateTime? _lastOpenAt; // когда последний раз грузили свежую ссылку
  bool _recovering = false; // идёт восстановление сессии (страница входа)
  bool _opening = false; // грузим свежую страницу - прячем старый контент
  bool _pendingPayment =
      false; // ярлык «Пополнить» на холодном старте - ждём загрузки

  
  /// ссылку считаем устаревшей через 15 минут - при возврате из фона обновим
  static const Duration _staleAfter = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemeController.mode.addListener(_onThemeChanged);
    QuickActionsService.homeRequested.addListener(_onHomeRequested);
    QuickActionsService.paymentRequested.addListener(_onPaymentRequested);
    BalanceStore.restore(); // показать последний известный баланс сразу
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('PullRefresh',
          onMessageReceived: (_) => _openCabinet())
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: CabinetNavigation.handleNavigationRequest,
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) async {
            // СНАЧАЛА красим (в т.ч. тёмная тема), пока скелетон ещё прикрывает -
            // иначе на миг видна белая страница до применения тёмного CSS
            await _controller.injectCabinetStyle(_cabinetDark);
            await _controller.injectPullToRefresh();
            await _controller.linkifyInformerPhones();
            if (_cabinetDark) {
              await Future.delayed(const Duration(milliseconds: 110));
            }
            if (mounted) {
              setState(() {
                _loading = false;
                _firstLoaded = true;
                _opening = false;
              });
            }
            if (!_offline) {
              await _controller.cacheSnapshot(_liveUrl ?? '');
              await _controller.extractBalance();
            }
            if (await _controller.isSessionExpired()) {
              if (!_recovering) {
                _recovering = true;
                _openCabinet();
              }
            } else {
              _recovering = false;
            }
            // отложенное «Пополнить» с холодного старта - теперь главная готова
            if (_pendingPayment && !_offline && _error == null) {
              _pendingPayment = false;
              _openPayment();
            }
          },
          onWebResourceError: (err) {
            // ошибка только основного документа (не вложенных ресурсов)
            if (err.isForMainFrame ?? true) {
              setState(() {
                _loading = false;
                _firstLoaded = true;
                _opening = false;
                _error = 'Не удалось загрузить кабинет. Потяните вниз '
                    'или нажмите «Обновить».';
              });
            }
          },
        ),
      );
    _openCabinet();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ThemeController.mode.removeListener(_onThemeChanged);
    QuickActionsService.homeRequested.removeListener(_onHomeRequested);
    QuickActionsService.paymentRequested.removeListener(_onPaymentRequested);
    super.dispose();
  }

  /// ярлык иконки «Личный кабинет» - открываем главную (Основную информацию)
  void _onHomeRequested() => _openCabinet();

  /// ярлык иконки «Пополнить» - открываем раздел пополнения
  void _onPaymentRequested() => _openPayment();

  /// смена темы приложением - перекрашиваем уже открытую страницу кабинета,
  /// не дожидаясь перезагрузки
  void _onThemeChanged() {
    _controller.setBackgroundColor(
        _cabinetDark ? const Color(0xFF0F141A) : Colors.white);
    _controller.runJavaScript(
        "var d=document.getElementById('interraDark');if(d)d.remove();");
    if (_cabinetDark) _controller.injectCabinetDark();
  }

  /// тёмная ли сейчас тема (для CSS кабинета)
  bool get _cabinetDark {
    final mode = ThemeController.mode.value;
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return mounted &&
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // при возврате из фона освежаем ссылку, если она могла протухнуть
    if (state == AppLifecycleState.resumed) {
      final last = _lastOpenAt;
      if (last == null || DateTime.now().difference(last) > _staleAfter) {
        _openCabinet();
      }
    }
  }

  /// внешние ссылки (`tel:`, `mailto:`, чужие домены с target=_blank)
  /// открываем в системных приложениях, не внутри WebView

  /// запрашивает свежую ссылку на ЛК и грузит «Основную информацию»
  /// «Обновить»: на подразделе перезагружаем текущую страницу (остаёмся в нём);
  /// на главной берём свежую ссылку - reload одноразового токена главной UTM5
  /// кидает на страницу входа. если reload подраздела всё же протухнет, сработает
  /// восстановление сессии и вернёт на главную
  Future<void> _refresh() async {
    if (_offline || _error != null) {
      _openCabinet();
      return;
    }
    final url = await _controller.currentUrl();
    if (url == null || url == _liveUrl || url.contains('oper=info')) {
      _openCabinet();
    } else {
      setState(() => _loading = true);
      _controller.reload();
    }
  }

  /// открывает раздел «Пополнение счёта» по тапу на баланс в шапке. берём ссылку
  /// прямо со страницы кабинета (там свежий токен сессии), иначе собираем из
  /// адреса главной. без сети - просто переоткрываем кабинет
  Future<void> _openPayment() async {
    if (_offline || _error != null) {
      _openCabinet();
      return;
    }
    // холодный старт по ярлыку: кабинет ещё не загружен - откроем его,
    // а к пополнению вернёмся, когда главная отрисуется (onPageFinished)
    if (_liveUrl == null) {
      _pendingPayment = true;
      _openCabinet();
      return;
    }
    try {
      final href = await _controller.extractPaymentLink();
      if (href != null) {
        setState(() => _loading = true);
        await _controller.loadRequest(Uri.parse(href));
        return;
      }
    } catch (e) {
      debugPrint('ссылка пополнения не найдена: $e');
    }
    // запасной вариант: собрать из адреса главной (aaainfo → aaasyspay)
    final base = _liveUrl;
    if (base != null && base.contains('aaainfo')) {
      final url = base
          .replaceFirst('aaainfo', 'aaasyspay')
          .replaceFirst('oper=info', 'oper=syspay');
      setState(() => _loading = true);
      await _controller.loadRequest(Uri.parse(url));
    } else {
      _openCabinet();
    }
  }

  Future<void> _openCabinet() async {
    setState(() {
      _error = null;
      _loading = true;
      _opening = true; // прикрываем старую страницу, пока грузится новая
    });

    final token = await AuthStore().appToken;
    if (token == null) {
      _resetToRegister();
      return;
    }

    final r = await BillingApi.openCabinet(token);
    if (!mounted) return;

    if (r.isOk) {
      _lastOpenAt = DateTime.now();
      _liveUrl = AppConfig.cabinetFromLoginParam(r.data!);
      setState(() => _offline = false);
      Analytics.cabinetOpened();
      // фон WebView под тему - чтобы во время загрузки не белел
      _controller.setBackgroundColor(
          _cabinetDark ? const Color(0xFF0F141A) : Colors.white);
      await _controller.loadRequest(Uri.parse(_liveUrl!));
      return;
    }

    // '0' - приложение не зарегистрировано (регистрация потеряна) → регистрация;
    // '1' - телефон отвязан от ЛК; пусто/сеть - временный сбой
    if (r.code == '0') {
      await AuthStore().clear();
      _resetToRegister();
      return;
    }

    // сетевой сбой: если есть кэш-снимок - показываем его в офлайн-режиме
    if (r.networkError && await _showCachedSnapshot()) return;

    setState(() {
      _loading = false;
      _firstLoaded = true;
      _opening = false;
      _error = r.networkError
          ? 'Нет связи с кабинетом. Проверьте интернет и обновите.'
          : r.code == '1'
              ? 'Телефон приложения отвязан от лицевого счёта. Обратитесь в Интерру.'
              : 'Не удалось открыть кабинет. Попробуйте обновить.';
    });
  }


  /// показывает кэш-снимок в офлайн-режиме. true - снимок был и отрисован
  Future<bool> _showCachedSnapshot() async {
    final cached = await PageCache.load();
    if (cached == null || !mounted) return false;
    setState(() {
      _offline = true;
      _error = null;
    });
    await _controller.loadHtmlString(cached.$1, baseUrl: cached.$2);
    return true;
  }

  void _resetToRegister() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
      (route) => false,
    );
  }

  Future<void> _goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    // на Android снизу уже есть системная навигация (назад/домой), поэтому своя
    // нижняя панель дублирует её и выглядит плохо: убираем панель целиком, а
    // «Главную» выносим в шапку слева от настроек. на iOS оставляем как было.
    final isAndroid = Platform.isAndroid;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          _controller.goBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Личный кабинет'),
          actions: [
            _balanceChip(),
            // на Android «Главная» живёт в шапке (слева от настроек),
            // т.к. нижней панели больше нет
            if (isAndroid)
              IconButton(
                icon: const Icon(Icons.home_rounded),
                tooltip: 'Главная',
                onPressed: _openCabinet,
              ),
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
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading && _firstLoaded && _error == null)
              const LinearProgressIndicator(
                color: AppColors.brand,
                backgroundColor: Colors.transparent,
              ),
            if (_offline && _error == null)
              Positioned(top: 0, left: 0, right: 0, child: _offlineBanner()),
            if (_error != null) _errorOverlay(),
            // скелетон прикрывает: первую загрузку, любое переоткрытие, а в
            // тёмной теме - и переходы между разделами (иначе новая страница
            // мелькает белым до применения тёмного CSS)
            if ((!_firstLoaded || _opening || (_loading && _cabinetDark)) &&
                _error == null)
              const CabinetSkeleton(),
          ],
        ),
        bottomNavigationBar: isAndroid
            ? null
            : BottomAppBar(
                height: 64,
                padding: EdgeInsets.zero,
                color: context.p.card,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: context.p.line)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navButton(
                        icon: Icons.arrow_back_ios_new,
                        label: 'Назад',
                        onTap: _goBack,
                      ),
                      _navButton(
                        icon: Icons.home_rounded,
                        label: 'Главная',
                        color: AppColors.brand,
                        big: true,
                        onTap: _openCabinet,
                      ),
                      _navButton(
                        icon: Icons.refresh,
                        label: 'Обновить',
                        onTap: _refresh,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  /// чип с нативным балансом в шапке. обновляется после каждой живой загрузки
  /// кабинета; при старте показывает последнее сохранённое значение (офлайн).
  /// Тап - обновить кабинет (и баланс вместе с ним)
  Widget _balanceChip() => ValueListenableBuilder<BalanceInfo?>(
        valueListenable: BalanceStore.notifier,
        builder: (context, info, _) {
          if (info == null) return const SizedBox.shrink();
          // на светлой шапке - мягкая тонированная плашка: синий при плюсе,
          // красный при минусе
          final negative = info.amount < 0;
          // при плюсе - синий; на тёмной теме берём светлее для контраста
          final dark = Theme.of(context).brightness == Brightness.dark;
          final color = negative
              ? AppColors.danger
              : (dark ? AppColors.brand : AppColors.brandInk);
          return Center(
            child: GestureDetector(
              onTap: _openPayment,
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet_rounded,
                        size: 15, color: color),
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

  /// кнопка нижней панели: только иконка (без подписи)
  Widget _navButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    bool big = false,
  }) {
    final c = color ?? context.p.inkMute;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Center(
          child: Icon(icon, color: c, size: big ? 28 : 24),
        ),
      ),
    );
  }

  /// полоска-уведомление о работе в офлайне (показаны кэшированные данные)
  Widget _offlineBanner() => Material(
        color: const Color(0xFFFFF4E5),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Нет сети — показаны последние данные',
                      style:
                          TextStyle(fontSize: 12.5, color: Color(0xFF8A5A1E))),
                ),
                GestureDetector(
                  onTap: _openCabinet,
                  child: const Text('Обновить',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent)),
                ),
              ],
            ),
          ),
        ),
      );

  /// брендовый экран ошибки/офлайна с мягким появлением
  Widget _errorOverlay() => Container(
        color: context.p.bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
                offset: Offset(0, (1 - t) * 12), child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_off_rounded,
                    color: AppColors.brand, size: 34),
              ),
              const SizedBox(height: 22),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.p.ink,
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openCabinet,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Обновить'),
                style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const DiagnosticsScreen(),
                  settings: const RouteSettings(name: 'diagnostics'),
                )),
                icon: const Icon(Icons.network_check_rounded, size: 20),
                label: const Text('Диагностика сети'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  minimumSize: const Size(200, 44),
                ),
              ),
            ],
          ),
        ),
      );
}
