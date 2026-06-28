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
  bool _autoLoginAttempted = false;

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
            await _maybeAutoLogin();
          },
        ),
      )
      // Грузим сразу страницу формы входа UTM5 (а не frameset корня),
      // чтобы поля user/pass были доступны для авто-логина.
      ..loadRequest(Uri.parse(AppConfig.loginUrl));
  }

  /// Если на странице есть форма входа UTM5 (поля user/pass) и сохранены
  /// учётные данные — подставляет их и отправляет форму.
  Future<void> _maybeAutoLogin() async {
    if (_autoLoginAttempted) return;
    final creds = await AuthStore().read();
    if (creds == null) return;

    final login = jsonEncode(creds.login);
    final password = jsonEncode(creds.password);
    // Форма может лежать в верхнем документе или внутри фрейма (UTM5 — frames),
    // поэтому пробуем и document, и все одно-доменные фреймы.
    final js = '''
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
        for(var i=0;i<window.frames.length;i++){
          if(fill(window.frames[i].document)) return 'submitted';
        }
        return 'no-form';
      })();
    ''';
    final result = await _controller.runJavaScriptReturningResult(js);
    if (result.toString().contains('submitted')) {
      _autoLoginAttempted = true;
    }
  }

  Future<void> _reload() async {
    _autoLoginAttempted = false;
    await _controller.reload();
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
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
              tooltip: 'Обновить',
            ),
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
      ),
    );
  }
}
