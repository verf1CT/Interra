import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config.dart';
import '../services/auth_store.dart';
import 'settings_screen.dart';

/// Главный экран — WebView с веб-кабинетом Интерра и авто-логином в UTM5.
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  bool _loginNavDone = false; // уже переходили на форму входа
  bool _fillDone = false; // уже подставили логин/пароль
  bool _busy = false; // защита от параллельных обработок
  bool _firstLoaded = false; // первая страница загрузилась
  String? _sessionToken; // токен сессии UTM5 (параметр login в URL кабинета)
  String _currentUrl = ''; // текущий адрес (диагностика)

  // Состояние страницы UTM5: форма входа / промежуточная «вход по паролю» / прочее.
  static const String _detectJs = '''
    (function(){
      function q(doc,sel){ try{ return doc.querySelector(sel); }catch(e){ return null; } }
      function scan(sel){
        if(q(document,sel)) return true;
        for(var i=0;i<window.frames.length;i++){ if(q(window.frames[i].document,sel)) return true; }
        return false;
      }
      if(scan("input[name='user']") && scan("input[name='pass']")) return 'form';
      if(scan("a[href*='oper=ident']")) return 'needlogin';
      return 'other';
    })();
  ''';

  /// Сессионный токен передаётся в параметре login (непустой) на адресах кабинета.
  String? _tokenFromUrl(String url) {
    final m = RegExp(r'[?&]login=([^&]+)').firstMatch(url);
    final v = m?.group(1);
    return (v == null || v.isEmpty) ? null : v;
  }

  void _captureToken(String url) {
    final t = _tokenFromUrl(url);
    if (t != null && t != _sessionToken) {
      _sessionToken = t;
      AuthStore().saveSession(t);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onUrlChange: (change) {
            final u = change.url;
            if (u != null) {
              setState(() => _currentUrl = u);
              _captureToken(u);
            }
          },
          onPageFinished: (url) async {
            setState(() {
              _loading = false;
              _firstLoaded = true;
              _currentUrl = url;
            });
            await _handlePage();
          },
        ),
      );
    _loadInitial();
  }

  /// Старт: пробуем сохранённый токен (вход без 2FA, если сессия жива),
  /// иначе грузим корень и идём через авто-логин.
  Future<void> _loadInitial() async {
    final token = await AuthStore().readSession();
    if (token != null && token.isNotEmpty) {
      _sessionToken = token;
      await _controller.loadRequest(Uri.parse(AppConfig.cabinetUrl(token)));
    } else {
      await _controller.loadRequest(Uri.parse(AppConfig.portalUrl));
    }
  }

  Future<void> _handlePage() async {
    if (_busy) return;
    _busy = true;
    try {
      final creds = await AuthStore().read();
      if (creds == null) return;

      // Фреймы UTM5 догружаются после основного документа — опрашиваем.
      for (var attempt = 0; attempt < 6; attempt++) {
        final state =
            (await _controller.runJavaScriptReturningResult(_detectJs)).toString();

        if (state.contains('form')) {
          if (!_fillDone) {
            final res =
                (await _controller.runJavaScriptReturningResult(_fillJs(creds)))
                    .toString();
            if (res.contains('submitted')) _fillDone = true;
          }
          return;
        }
        if (state.contains('needlogin')) {
          if (!_loginNavDone) {
            _loginNavDone = true;
            await _controller.loadRequest(Uri.parse(AppConfig.loginUrl));
          }
          return;
        }

        // 'other': если это страница кабинета (в URL есть токен) — запоминаем.
        final cur = await _controller.currentUrl() ?? _currentUrl;
        if (_tokenFromUrl(cur) != null) {
          _captureToken(cur);
          return;
        }
        // Иначе, возможно, фрейм/редирект ещё в процессе — ждём.
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      _busy = false;
    }
  }

  String _fillJs(({String login, String password}) creds) {
    final login = jsonEncode(creds.login);
    final password = jsonEncode(creds.password);
    return '''
      (function(){
        function fill(doc){
          try{
            var u=doc.querySelector("input[name='user']");
            var p=doc.querySelector("input[name='pass']");
            if(u&&p){ u.value=$login; p.value=$password; if(u.form){u.form.submit();} return true; }
          }catch(e){}
          return false;
        }
        if(fill(document)) return 'submitted';
        for(var i=0;i<window.frames.length;i++){ if(fill(window.frames[i].document)) return 'submitted'; }
        return 'no-form';
      })();
    ''';
  }

  Future<void> _goHome() async {
    _loginNavDone = false;
    _fillDone = false;
    final t = _sessionToken;
    final url = t != null ? AppConfig.cabinetUrl(t) : AppConfig.portalUrl;
    await _controller.loadRequest(Uri.parse(url));
  }

  Future<void> _reload() async {
    _loginNavDone = false;
    _fillDone = false;
    await _controller.reload();
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
          backgroundColor: const Color(0xFFE3000F),
          foregroundColor: Colors.white,
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
            if (_loading && _firstLoaded)
              const LinearProgressIndicator(
                color: Color(0xFFE3000F),
                backgroundColor: Colors.transparent,
              ),
            // Брендовая заставка на первую загрузку кабинета.
            if (!_firstLoaded)
              Container(
                color: const Color(0xFFF6F7F9),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF3B30), Color(0xFFE3000F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.wifi_rounded,
                          color: Colors.white, size: 38),
                    ),
                    const SizedBox(height: 22),
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                          color: Color(0xFFE3000F), strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 16),
                    Text('Загрузка кабинета…',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
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
                  onPressed: _goBack,
                ),
                IconButton(
                  icon: const Icon(Icons.home_rounded,
                      color: Color(0xFFE3000F)),
                  iconSize: 32,
                  tooltip: 'Главная',
                  onPressed: _goHome,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 24),
                  color: Colors.grey.shade700,
                  tooltip: 'Обновить',
                  onPressed: _reload,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
