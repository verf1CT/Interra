import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config.dart';
import '../theme.dart';
import '../services/auth_store.dart';
import '../services/billing_api.dart';
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
      await _controller
          .loadRequest(Uri.parse(AppConfig.cabinetFromLoginParam(r.data!)));
      return;
    }

    // '0' — приложение не зарегистрировано (регистрация потеряна) → регистрация;
    // '1' — телефон отвязан от ЛК; пусто/сеть — временный сбой.
    if (r.code == '0') {
      await AuthStore().clear();
      _resetToRegister();
      return;
    }
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

  /// Pull-to-refresh: в самом верху страницы тянем вниз → перезагрузка.
  Future<void> _injectPullToRefresh() async {
    try {
      await _controller.runJavaScript('''
        (function(){
          if(window.__interraPTR) return; window.__interraPTR = true;
          var startY = 0, pulling = false;
          document.addEventListener('touchstart', function(e){
            if((window.scrollY||document.documentElement.scrollTop)===0){
              startY = e.touches[0].clientY; pulling = true;
            } else { pulling = false; }
          }, {passive:true});
          document.addEventListener('touchmove', function(e){
            if(!pulling) return;
            if(e.touches[0].clientY - startY > 90){
              pulling = false;
              if(window.PullRefresh) window.PullRefresh.postMessage('refresh');
            }
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
            if (_error != null) _errorOverlay(),
            if (!_firstLoaded) const CabinetSkeleton(),
          ],
        ),
        bottomNavigationBar: BottomAppBar(
          height: 58,
          padding: EdgeInsets.zero,
          color: Colors.white,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE9EBEF))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 22),
                  color: Colors.grey.shade700,
                  tooltip: 'Назад',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _goBack();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.home_rounded, color: Color(0xFFF4752D)),
                  iconSize: 32,
                  tooltip: 'Главная',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _openCabinet();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 24),
                  color: Colors.grey.shade700,
                  tooltip: 'Обновить',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _controller.reload();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorOverlay() => Container(
        color: AppColors.bg,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 22),
            FilledButton(onPressed: _openCabinet, child: const Text('Обновить')),
          ],
        ),
      );
}
