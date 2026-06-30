import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config.dart';
import '../theme.dart';
import '../services/auth_store.dart';
import '../services/billing_api.dart';
import '../services/page_cache.dart';
import '../widgets/cabinet_skeleton.dart';
import 'register_screen.dart';
import 'settings_screen.dart';

/// Главный экран — WebView с веб-кабинетом Интерра.
///
/// Схема `bbb`: при каждом открытии берём свежую ссылку на ЛК через
/// `cmd=open&app={token}` и грузим страницу «Основная информация». Ссылка
/// живёт ~30 минут, поэтому при возврате из фона и протухшей сессии ссылку
/// перезапрашиваем автоматически.
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
  String? _liveUrl; // URL последней «живой» (сетевой) загрузки — для кэша
  DateTime? _lastOpenAt; // когда последний раз грузили свежую ссылку

  /// Свой хост держим внутри WebView, всё остальное — наружу.
  static const String _host = 'stat.interra.ru';

  /// Ссылку считаем устаревшей через 15 минут — при возврате из фона обновим.
  static const Duration _staleAfter = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('PullRefresh',
          onMessageReceived: (_) => _openCabinet())
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigation,
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) async {
            setState(() {
              _loading = false;
              _firstLoaded = true;
            });
            await _injectPullToRefresh();
            // Снимок для офлайна делаем только с «живой» сетевой страницы,
            // а не когда сами отрисовали кэш через loadHtmlString.
            if (!_offline) await _cacheSnapshot();
            await _recoverIfSessionExpired();
          },
          onWebResourceError: (err) {
            // Ошибка только основного документа (не вложенных ресурсов).
            if (err.isForMainFrame ?? true) {
              setState(() {
                _loading = false;
                _firstLoaded = true;
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // При возврате из фона освежаем ссылку, если она могла протухнуть.
    if (state == AppLifecycleState.resumed) {
      final last = _lastOpenAt;
      if (last == null || DateTime.now().difference(last) > _staleAfter) {
        _openCabinet();
      }
    }
  }

  /// Внешние ссылки (`tel:`, `mailto:`, чужие домены с target=_blank)
  /// открываем в системных приложениях, не внутри WebView.
  NavigationDecision _handleNavigation(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.navigate;
    final scheme = uri.scheme.toLowerCase();

    if (scheme == 'tel' || scheme == 'mailto' || scheme == 'sms') {
      _launchExternal(uri);
      return NavigationDecision.prevent;
    }
    if ((scheme == 'http' || scheme == 'https') && uri.host != _host) {
      _launchExternal(uri);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Не удалось открыть $uri: $e');
    }
  }

  /// Запрашивает свежую ссылку на ЛК и грузит «Основную информацию».
  Future<void> _openCabinet() async {
    setState(() {
      _error = null;
      _loading = true;
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
      await _controller.loadRequest(Uri.parse(_liveUrl!));
      return;
    }

    // '0' — приложение не зарегистрировано (регистрация потеряна) → регистрация;
    // '1' — телефон отвязан от ЛК; пусто/сеть — временный сбой.
    if (r.code == '0') {
      await AuthStore().clear();
      _resetToRegister();
      return;
    }

    // Сетевой сбой: если есть кэш-снимок — показываем его в офлайн-режиме.
    if (r.networkError && await _showCachedSnapshot()) return;

    setState(() {
      _loading = false;
      _firstLoaded = true;
      _error = r.networkError
          ? 'Нет связи с кабинетом. Проверьте интернет и обновите.'
          : r.code == '1'
              ? 'Телефон приложения отвязан от лицевого счёта. Обратитесь в Интерру.'
              : 'Не удалось открыть кабинет. Попробуйте обновить.';
    });
  }

  /// Сохраняет снимок текущей «живой» страницы для показа без сети.
  Future<void> _cacheSnapshot() async {
    final url = _liveUrl;
    if (url == null) return;
    try {
      final res = await _controller
          .runJavaScriptReturningResult('document.documentElement.outerHTML');
      var html = res is String ? res : res.toString();
      // Android отдаёт JSON-строку (в кавычках с экранированием) — раскодируем.
      if (html.length >= 2 && html.startsWith('"') && html.endsWith('"')) {
        try {
          html = jsonDecode(html) as String;
        } catch (_) {/* iOS отдаёт сырой HTML — оставляем как есть */}
      }
      if (html.contains('<')) await PageCache.save(html, url);
    } catch (e) {
      debugPrint('Снимок кабинета не сохранён: $e');
    }
  }

  /// Показывает кэш-снимок в офлайн-режиме. true — снимок был и отрисован.
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

  /// Если UTM5 уронил сессию и показал форму входа по паролю — токен-ссылка
  /// протухла; молча перезапрашиваем свежую через `cmd=open`.
  Future<void> _recoverIfSessionExpired() async {
    try {
      final res = await _controller.runJavaScriptReturningResult('''
        (function(){
          try{ return (document.querySelector("input[name='pass']") ||
                       document.querySelector("a[href*='oper=ident']")) ? '1':'0'; }
          catch(e){ return '0'; }
        })();
      ''');
      if (res.toString().contains('1')) {
        // Защита от цикла: обновляем не чаще раза в несколько секунд.
        final last = _lastOpenAt;
        if (last == null ||
            DateTime.now().difference(last) > const Duration(seconds: 5)) {
          _openCabinet();
        }
      }
    } catch (_) {/* страница могла уже смениться — не критично */}
  }

  /// Pull-to-refresh: в самом верху страницы тянем вниз — вся страница уезжает
  /// вниз, сверху появляется значок и поворачивается по мере вытягивания; за
  /// порогом он крутится непрерывно и кабинет перезагружается.
  Future<void> _injectPullToRefresh() async {
    try {
      await _controller.runJavaScript(r'''
        (function(){
          if(window.__interraPTR) return; window.__interraPTR = true;

          var THRESHOLD = 70, MAX = 120;
          var startY = 0, pull = 0, pulling = false, triggered = false;

          // Стили: непрерывное вращение + мягкий возврат страницы.
          var st = document.createElement('style');
          st.textContent =
            '@keyframes interraSpin{to{transform:rotate(360deg)}}' +
            '#interraPTR{position:fixed;top:0;left:50%;margin-left:-18px;' +
            'width:36px;height:36px;z-index:2147483647;opacity:0;' +
            'pointer-events:none;will-change:transform,opacity;}' +
            '#interraPTR svg{display:block;width:36px;height:36px;}' +
            '#interraPTR .ring{fill:none;stroke:#3C98D4;stroke-width:4;' +
            'stroke-linecap:round;stroke-dasharray:80;stroke-dashoffset:20;}';
          document.head.appendChild(st);

          // Значок вешаем на <html>, а не на <body>: у body стоит transform
          // (страница уезжает вниз), и значок-потомок body двигался бы вместе с
          // ней. На html (он не трансформируется) позиционируем его сами —
          // строго внутри образовавшегося зазора, не залезая на контент.
          var ind = document.createElement('div');
          ind.id = 'interraPTR';
          ind.innerHTML =
            '<svg viewBox="0 0 36 36"><circle class="ring" cx="18" cy="18" r="15"/></svg>';
          document.documentElement.appendChild(ind);

          var doc = document.documentElement;
          function atTop(){ return (window.scrollY||doc.scrollTop||0) <= 0; }

          function setPull(p){
            pull = p;
            var clamped = Math.min(p, MAX);
            document.body.style.transform = 'translateY(' + clamped + 'px)';
            ind.style.opacity = Math.min(clamped / THRESHOLD, 1);
            // Значок держим ВНУТРИ зазора: его низ (iy+36) не ниже края контента
            // (контент начинается на уровне clamped). При малом зазоре значок
            // уезжает вверх за кромку — это нормально (он там почти прозрачный).
            var iy = clamped - 40;
            // Поворот пропорционален вытягиванию + лёгкий рост значка.
            var scale = 0.6 + Math.min(clamped / MAX, 1) * 0.4;
            ind.style.transform =
              'translateY(' + iy + 'px) rotate(' + (clamped * 3) + 'deg) scale(' + scale + ')';
          }

          function reset(animate){
            if(animate){
              document.body.style.transition = 'transform .25s ease';
              ind.style.transition = 'transform .25s ease, opacity .25s ease';
            }
            document.body.style.transform = '';
            ind.style.opacity = 0;
            ind.style.transform = 'translateY(0) rotate(0deg) scale(0.6)';
            ind.style.animation = '';
            setTimeout(function(){
              document.body.style.transition = '';
              ind.style.transition = '';
            }, 260);
            pull = 0; pulling = false; triggered = false;
          }

          document.addEventListener('touchstart', function(e){
            if(triggered) return;
            if(atTop()){ startY = e.touches[0].clientY; pulling = true; }
            else { pulling = false; }
          }, {passive:true});

          document.addEventListener('touchmove', function(e){
            if(!pulling || triggered) return;
            var delta = e.touches[0].clientY - startY;
            if(delta <= 0 || !atTop()){
              if(pull > 0) reset(true);
              return;
            }
            e.preventDefault(); // перехватываем нативный скролл только тут
            setPull(delta * 0.5); // резиновое замедление
          }, {passive:false});

          function end(){
            if(!pulling || triggered) return;
            if(Math.min(pull, MAX) >= THRESHOLD){
              // Запуск: непрерывное вращение + перезагрузка кабинета.
              triggered = true;
              document.body.style.transition = 'transform .2s ease';
              document.body.style.transform = 'translateY(50px)';
              ind.style.transition = 'transform .2s ease, opacity .2s ease';
              // Зазор 50px → значок (36px) центрируем в нём, не на контенте.
              ind.style.transform = 'translateY(8px) scale(1)';
              var svg = ind.querySelector('svg');
              svg.style.transformOrigin = '50% 50%';
              svg.style.animation = 'interraSpin .8s linear infinite';
              ind.style.opacity = 1;
              if(window.PullRefresh) window.PullRefresh.postMessage('refresh');
            } else {
              reset(true);
            }
          }
          document.addEventListener('touchend', end, {passive:true});
          document.addEventListener('touchcancel', function(){
            if(!triggered) reset(true);
          }, {passive:true});
        })();
      ''');
    } catch (_) {}
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
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Настройки',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
            if (!_firstLoaded) const CabinetSkeleton(),
          ],
        ),
        bottomNavigationBar: BottomAppBar(
          height: 64,
          padding: EdgeInsets.zero,
          color: Colors.white,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
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
                  color: AppColors.accent,
                  big: true,
                  onTap: _openCabinet,
                ),
                _navButton(
                  icon: Icons.refresh,
                  label: 'Обновить',
                  onTap: () => _controller.reload(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Кнопка нижней панели: иконка + подпись.
  Widget _navButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    bool big = false,
  }) {
    final c = color ?? Colors.grey.shade700;
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: c, size: big ? 28 : 22),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    color: c,
                    fontSize: 11,
                    fontWeight: big ? FontWeight.w600 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  /// Полоска-уведомление о работе в офлайне (показаны кэшированные данные).
  Widget _offlineBanner() => Material(
        color: const Color(0xFFFFF4E5),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Нет сети — показаны последние данные',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF8A5A1E))),
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

  /// Брендовый экран ошибки/офлайна с мягким появлением.
  Widget _errorOverlay() => Container(
        color: AppColors.bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.brand, AppColors.accent],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brand.withValues(alpha: 0.30),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(Icons.wifi_off_rounded,
                    color: Colors.white, size: 40),
              ),
              const SizedBox(height: 22),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF1C1F24),
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
            ],
          ),
        ),
      );
}
