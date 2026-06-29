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

  // Один логин-цикл за сессию навигации, чтобы не зациклиться:
  bool _loginNavDone = false; // уже переходили на форму входа
  bool _fillDone = false; // уже подставили логин/пароль
  bool _busy = false; // защита от параллельных обработок

  // Определяем состояние страницы UTM5: форма входа / промежуточная страница
  // со ссылкой «вход по паролю» / прочее (кабинет). Учитываем фреймы.
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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (url) async {
            setState(() => _loading = false);
            await _handlePage();
          },
        ),
      )
      // Грузим сам кабинет: если сессия в куках жива — откроется сразу,
      // без повторного входа (и без страницы подтверждения телефона).
      ..loadRequest(Uri.parse(AppConfig.portalUrl));
  }

  /// Логика авто-логина: подставляем учётные данные только когда реально
  /// видим форму входа; на промежуточной странице — переходим к форме.
  /// Фреймы UTM5 догружаются после основного документа, поэтому опрашиваем
  /// состояние несколько раз.
  Future<void> _handlePage() async {
    if (_busy) return;
    _busy = true;
    try {
      final creds = await AuthStore().read();
      if (creds == null) return;

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
          // Сессии нет — переходим прямо к форме входа (один раз).
          if (!_loginNavDone) {
            _loginNavDone = true;
            await _controller.loadRequest(Uri.parse(AppConfig.loginUrl));
          }
          return;
        }
        // 'other' — возможно, фрейм ещё грузится; ждём и пробуем снова.
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
    await _controller.loadRequest(Uri.parse(AppConfig.portalUrl));
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
            if (_loading)
              const LinearProgressIndicator(
                color: Color(0xFFE3000F),
                backgroundColor: Colors.transparent,
              ),
          ],
        ),
        bottomNavigationBar: BottomAppBar(
          height: 56,
          padding: EdgeInsets.zero,
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Назад',
                onPressed: _goBack,
              ),
              IconButton(
                icon: const Icon(Icons.home, color: Color(0xFFE3000F)),
                iconSize: 30,
                tooltip: 'Главная',
                onPressed: _goHome,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Обновить',
                onPressed: _reload,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
