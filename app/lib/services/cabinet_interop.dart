import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'balance_store.dart';
import 'page_cache.dart';

/// Расширение для WebViewController, инкапсулирующее всю логику взаимодействия
/// с JavaScript (Interop) для кабинета UTM5.
extension CabinetInterop on WebViewController {
  /// вживляет фирменные стили в страницу кабинета UTM5
  Future<void> injectCabinetStyle(bool dark) async {
    try {
      final css = await rootBundle.loadString('assets/web/cabinet.css');
      final escapedCss = css.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(RegExp(r'\r?\n'), '');
      await runJavaScript('''
        (function(){
          var pb = document.getElementById('parent_bunny');
          if (pb) { pb.remove(); }
          if(document.getElementById('interraTheme')) return;
          var css = "$escapedCss";
          var st = document.createElement('style');
          st.id = 'interraTheme';
          st.textContent = css;
          document.head.appendChild(st);
        })();
      ''');
      if (dark) await injectCabinetDark();
    } catch (_) {}
  }

  /// тёмная тема для страниц кабинета
  Future<void> injectCabinetDark() async {
    try {
      final css = await rootBundle.loadString('assets/web/cabinet_dark.css');
      final escapedCss = css.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(RegExp(r'\r?\n'), '');
      await runJavaScript('''
        (function(){
          if(document.getElementById('interraDark')) return;
          var css = "$escapedCss";
          var st = document.createElement('style');
          st.id = 'interraDark';
          st.textContent = css;
          document.head.appendChild(st);
        })();
      ''');
    } catch (_) {}
  }

  /// достаёт баланс и номер лицевого счёта из текста живой страницы кабинета
  Future<void> extractBalance() async {
    try {
      final res = await runJavaScriptReturningResult(r"""
        (function(){
          try{
            var t = document.body.innerText || '';
            var b = t.match(/Баланс[\s:]*(-?[\d\s ]+(?:[.,]\d+)?)\s*руб/);
            var a = t.match(/(?:Электронный|Лицевой)\s+счёт[\s:]*([0-9]{3,})/);
            return JSON.stringify({b: b ? b[1] : '', a: a ? a[1] : ''});
          }catch(e){ return '{}'; }
        })();
      """);
      final map = _decodeJsResult(res);
      final amount = BalanceStore.parseAmount((map['b'] ?? '').toString());
      final account = (map['a'] ?? '').toString();
      if (amount != null) {
        await BalanceStore.update(amount, account: account.isEmpty ? null : account);
      }
    } catch (e) {
      debugPrint('Баланс не извлечён: $e');
    }
  }

  /// сохраняет снимок текущей «живой» страницы для показа без сети
  Future<void> cacheSnapshot(String url) async {
    try {
      final res = await runJavaScriptReturningResult('document.documentElement.outerHTML');
      var html = res is String ? res : res.toString();
      if (html.length >= 2 && html.startsWith('"') && html.endsWith('"')) {
        try { html = jsonDecode(html) as String; } catch (_) {}
      }
      if (html.contains('<')) await PageCache.save(html, url);
    } catch (e) {
      debugPrint('Снимок кабинета не сохранён: $e');
    }
  }

  /// проверяет, уронил ли UTM5 сессию и показал ли форму входа
  Future<bool> isSessionExpired() async {
    try {
      final res = await runJavaScriptReturningResult('''
        (function(){
          try{ return (document.querySelector("input[name='pass']") ||
                       document.querySelector("a[href*='oper=ident']")) ? '1':'0'; }
          catch(e){ return '0'; }
        })();
      ''');
      return res.toString().contains('1');
    } catch (_) {
      return false;
    }
  }

  /// pull-to-refresh
  Future<void> injectPullToRefresh() async {
    try {
      final js = await rootBundle.loadString('assets/web/pull_to_refresh.js');
      await runJavaScript(js);
    } catch (_) {}
  }

  /// linkify_phones
  Future<void> linkifyInformerPhones() async {
    try {
      final js = await rootBundle.loadString('assets/web/linkify_phones.js');
      await runJavaScript(js);
    } catch (_) {}
  }

  /// ищет ссылку на раздел «Пополнение счёта» на текущей странице
  Future<String?> extractPaymentLink() async {
    try {
      final res = await runJavaScriptReturningResult('''
        (function(){
          var a = document.querySelector("a[href*='oper=syspay']");
          return a ? a.href : '';
        })();
      ''');
      var href = res is String ? res : res.toString();
      if (href.startsWith('"') && href.endsWith('"')) {
        href = jsonDecode(href) as String;
      }
      if (href.contains('oper=syspay')) return href;
    } catch (e) {
      debugPrint('ссылка пополнения не найдена: $e');
    }
    return null;
  }

  Map<String, dynamic> _decodeJsResult(Object? res) {
    try {
      var s = res is String ? res : res.toString();
      dynamic decoded = jsonDecode(s);
      if (decoded is String) decoded = jsonDecode(decoded);
      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    } catch (_) {
      return {};
    }
  }
}
