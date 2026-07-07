import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config.dart';
import '../theme.dart';
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

  /// свой хост держим внутри WebView, всё остальное - наружу
  static const String _host = 'stat.interra.ru';

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
          onNavigationRequest: _handleNavigation,
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) async {
            // СНАЧАЛА красим (в т.ч. тёмная тема), пока скелетон ещё прикрывает -
            // иначе на миг видна белая страница до применения тёмного CSS
            await _injectCabinetStyle();
            await _injectPullToRefresh();
            await _linkifyInformerPhones();
            // runJavaScript возвращается, как только стиль добавлен в DOM, но
            // WebView перерисовывается под тёмный CSS лишь на следующем кадре -
            // ждём пару кадров, иначе при снятии скелетона мелькнёт белым
            if (_cabinetDark) {
              await Future.delayed(const Duration(milliseconds: 110));
            }
            if (mounted) {
              setState(() {
                _loading = false;
                _firstLoaded = true;
                _opening =
                    false; // теперь снимаем заглушку - страница уже покрашена
              });
            }
            // снимок для офлайна делаем только с «живой» сетевой страницы,
            // а не когда сами отрисовали кэш через loadHtmlString
            if (!_offline) {
              await _cacheSnapshot();
              await _extractBalance();
            }
            await _recoverIfSessionExpired();
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
    if (_cabinetDark) _injectCabinetDark();
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
      final res = await _controller.runJavaScriptReturningResult('''
        (function(){
          var a = document.querySelector("a[href*='oper=syspay']");
          return a ? a.href : '';
        })();
      ''');
      var href = res is String ? res : res.toString();
      if (href.startsWith('"') && href.endsWith('"')) {
        href = jsonDecode(href) as String; // android отдаёт строку в кавычках
      }
      if (href.contains('oper=syspay')) {
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

  /// сохраняет снимок текущей «живой» страницы для показа без сети
  Future<void> _cacheSnapshot() async {
    final url = _liveUrl;
    if (url == null) return;
    try {
      final res = await _controller
          .runJavaScriptReturningResult('document.documentElement.outerHTML');
      var html = res is String ? res : res.toString();
      // android отдаёт JSON-строку (в кавычках с экранированием) - раскодируем
      if (html.length >= 2 && html.startsWith('"') && html.endsWith('"')) {
        try {
          html = jsonDecode(html) as String;
        } catch (_) {/* iOS отдаёт сырой HTML - оставляем как есть */}
      }
      if (html.contains('<')) await PageCache.save(html, url);
    } catch (e) {
      debugPrint('Снимок кабинета не сохранён: $e');
    }
  }

  /// достаёт баланс и номер лицевого счёта из текста живой страницы кабинета
  /// и кладёт в [BalanceStore]. страницы без нужных полей (отчёты и т.п.) просто
  /// не совпадут с шаблоном - значения останутся прежними
  Future<void> _extractBalance() async {
    try {
      final res = await _controller.runJavaScriptReturningResult(r"""
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
        await BalanceStore.update(amount,
            account: account.isEmpty ? null : account);
      }
    } catch (e) {
      debugPrint('Баланс не извлечён: $e');
    }
  }

  /// вживляет фирменные стили в страницу кабинета UTM5, чтобы она выглядела
  /// частью приложения (шрифт, цвета, отступы, скругления). только визуальные
  /// свойства - вёрстку и работу форм не ломаем. вставляем один раз (по id)
  Future<void> _injectCabinetStyle() async {
    final dark = _cabinetDark;
    try {
      await _controller.runJavaScript(r'''
        (function(){
          // убираем рекламный попап «кот» (#parent_bunny) - даже при повторе
          var pb = document.getElementById('parent_bunny');
          if (pb) { pb.remove(); }
          if(document.getElementById('interraTheme')) return;
          var css = ""
          // ── базовая типографика/цвета + защита от переполнения ──
          + "html,body{max-width:100%;overflow-x:hidden;}"
          + "*{word-break:break-word;overflow-wrap:anywhere;}"
          + "body{font-family:-apple-system,'SF Pro Text','Segoe UI',Roboto,sans-serif !important;"
          +   "color:#12181D !important;line-height:1.45;background:#ffffff !important;}"
          + "a{color:#206FA6 !important;text-decoration:none;}"
          + "a:active{opacity:.55;}"
          + "hr{border:none;border-top:1px solid #E4EAF0;}"
          + "img{max-width:100%;height:auto;}"
          // ── шапка кабинета: логотип дублирует шапку приложения - прячем,
          //    бургер (меню разделов) оставляем ──
          + ".header-logo{display:none !important;}"
          + ".header{margin-bottom:4px !important;justify-content:flex-end !important;}"
          + ".main{padding:12px 0 !important;}"
          // #aaatds: на некоторых страницах (PremiumTV) инлайн-JS насильно
          //   ставит width/height 250px и фоновую картинку - контент зажимается
          //   в квадрат. сбрасываем на нормальную ширину
          + "#aaatds{padding:0 16px !important;width:auto !important;height:auto !important;"
          +   "min-height:0 !important;background:none !important;background-image:none !important;"
          +   "display:block;box-sizing:border-box;}"
          // рекламный попап «кот» (/bunny/rabbit*.js вставляет #parent_bunny) - прячем
          + "#parent_bunny{display:none !important;}"
          // ── информер (телефон/адрес) → аккуратная карточка с оранжевой
          //    рамкой ВОКРУГ ВСЕГО блока (в utm7 рамка висит на ячейке) ──
          + ".b-informer{background:none !important;border:none !important;"
          +   "margin:0 0 16px 0 !important;max-width:100% !important;}"
          + ".b-informer tr td{border:1.5px solid #F77D31 !important;border-radius:14px;"
          +   "padding:14px 16px !important;background:#FFF6EF !important;"
          +   "font-size:13px !important;line-height:1.55;color:#6B5340 !important;}"
          + ".b-informer a,.b-informer a font{color:#C8571A !important;font-weight:600;}"
          // ── счёт → НЕ таблица, а список полей: подпись капсом сверху,
          //    значение крупно снизу (перебиваем .b-account tr td из utm7) ──
          + ".b-account{width:100% !important;margin:6px 0 0 0 !important;border:none !important;"
          +   "border-collapse:collapse !important;background:none !important;table-layout:fixed;}"
          + ".b-account thead{display:none !important;}"
          + ".b-account tr{display:block;padding:11px 0;border-bottom:1px solid #EEF1F4;}"
          + ".b-account tr:last-child{border-bottom:none;}"
          + ".b-account tr td{display:block !important;border:none !important;"
          +   "padding:0 !important;text-align:left !important;}"
          + ".b-account td[align=right]{color:#98A5B0 !important;font-size:11px !important;"
          +   "font-weight:600 !important;text-transform:uppercase;letter-spacing:.4px;"
          +   "margin-bottom:3px;}"
          + ".b-account td[align=right] b{font-weight:600 !important;}"
          + ".b-account td:not([align=right]){font-size:16px !important;font-weight:700 !important;"
          +   "color:#141A1F !important;}"
          + ".b-account span,.b-account td font{font-weight:700 !important;"
          +   "color:#141A1F !important;font-size:16px !important;}"
          // ── меню разделов (открывается бургером) ──
          + ".nav-link.--active{color:#3A96D6 !important;}"
          // ── вкладки внутри раздела (.b-tab, напр. операции/сессии) →
          //    чёткие подчёркнутые табы (таблицу разворачиваем в строку) ──
          + ".b-tab,.b-tab tbody,.b-tab tr{display:block !important;background:none !important;"
          +   "border:none !important;}"
          + ".b-tab{border-bottom:1px solid #E7ECF1 !important;margin:0 0 18px 0 !important;"
          +   "white-space:nowrap;}"
          + ".b-tab td{display:inline-block !important;padding:0 !important;background:none !important;"
          +   "border:none !important;vertical-align:bottom;}"
          + ".b-tab td[width='99%']{display:none !important;}"
          + ".b-tab td.active,.b-tab td a{display:inline-block;padding:11px 3px !important;"
          +   "margin-right:26px;font-size:15px;font-weight:600;color:#5A6773 !important;"
          +   "text-decoration:none !important;border-bottom:2.5px solid transparent;}"
          + ".b-tab td.active{color:#141A1F !important;border-bottom-color:#3A96D6 !important;"
          +   "font-weight:700 !important;}"
          + ".b-tab td.active b{font-weight:700 !important;}"
          // ── заголовок раздела (.t) ──
          + ".t{display:block;font-size:15px !important;font-weight:700 !important;"
          +   "color:#141A1F !important;margin:18px 0 8px 0 !important;}"
          // ── таблицы данных (отчёты, история) → чистая таблица ──
          + "#aaatds table:not(.b-tab):not(.b-content):not(.b-account):not(.b-informer){"
          +   "width:100% !important;border-collapse:collapse !important;margin:8px 0 !important;}"
          + "#aaatds table:not(.b-tab):not(.b-content):not(.b-account):not(.b-informer) td,"
          + "#aaatds table:not(.b-tab):not(.b-content):not(.b-account):not(.b-informer) th{"
          +   "padding:9px 10px !important;border:none !important;"
          +   "border-bottom:1px solid #EEF1F4 !important;font-size:13px !important;"
          +   "text-align:left !important;}"
          + "#aaatds table:not(.b-tab):not(.b-content):not(.b-account):not(.b-informer) th{"
          +   "color:#98A5B0 !important;font-weight:600 !important;text-transform:uppercase;"
          +   "font-size:11px !important;letter-spacing:.3px;}"
          + "#aaatds table:not(.b-tab):not(.b-content):not(.b-account):not(.b-informer) "
          +   "tr:nth-child(even) td{background:#FAFBFC !important;}"
          // ── экран входа в раздел (.login / .btn7) → под приложение ──
          + ".login{max-width:420px;margin:22px auto !important;}"
          + ".login-title h2{font-size:20px !important;font-weight:800 !important;"
          +   "color:#141A1F !important;text-align:center;letter-spacing:-.4px;margin:0 0 16px 0 !important;}"
          + ".login-control{display:flex !important;flex-direction:column;gap:10px;}"
          + ".btn7{display:block !important;padding:14px 16px !important;border-radius:12px !important;"
          +   "text-align:center;font-size:15px;font-weight:700;text-decoration:none !important;"
          +   "box-sizing:border-box;border:none !important;}"
          + "a.btn7{background:#3A96D6 !important;color:#fff !important;}"
          + "div.btn7{background:#F1F4F8 !important;color:#5A6773 !important;"
          +   "font-weight:500;font-size:13px;line-height:1.5;}"
          + "div.btn7 span{padding:2px 0 !important;display:inline;}"
          // ── поля ввода: в utm7 у select жёсткий height:28px → текст
          //    обрезался. сбрасываем высоту, задаём нормальные отступы ──
          + "input:not([type=submit]):not([type=button]):not([type=checkbox])"
          +   ":not([type=radio]):not([type=hidden]),textarea{height:auto !important;"
          +   "min-height:46px !important;line-height:1.3 !important;font-size:16px !important;"
          +   "padding:12px 14px !important;border:1px solid #E4EAF0 !important;"
          +   "border-radius:12px !important;background:#fff !important;color:#141A1F !important;"
          +   "box-sizing:border-box;max-width:100%;margin:6px 0 8px 0;"
          +   "font-family:-apple-system,sans-serif !important;}"
          // ── выпадающие списки (год/месяц, пакеты ТВ и т.п.): свой вид,
          //    кастомная стрелка, высота под шрифт - текст помещается ──
          + "select{-webkit-appearance:none !important;appearance:none !important;"
          +   "height:auto !important;min-height:46px !important;line-height:1.3 !important;"
          +   "font-size:16px !important;padding:12px 42px 12px 14px !important;"
          +   "border:1px solid #E4EAF0 !important;border-radius:12px !important;"
          +   "background-color:#fff !important;color:#141A1F !important;max-width:100%;"
          +   "margin:6px 8px 8px 0;vertical-align:middle;box-sizing:border-box;"
          +   "font-family:-apple-system,sans-serif !important;background-repeat:no-repeat;"
          +   "background-position:right 14px center;background-size:15px;"
          +   "background-image:url(data:image/svg+xml,%3Csvg%20xmlns=%27http://www.w3.org/2000/svg%27"
          +   "%20width=%2716%27%20height=%2716%27%20viewBox=%270%200%2024%2024%27%20fill=%27none%27"
          +   "%20stroke=%27%235A6773%27%20stroke-width=%272.4%27%20stroke-linecap=%27round%27"
          +   "%20stroke-linejoin=%27round%27%3E%3Cpolyline%20points=%276%209%2012%2015%2018%209%27"
          +   "/%3E%3C/svg%3E) !important;}"
          + "input:focus,select:focus,textarea:focus{outline:none;"
          +   "border-color:#3A96D6 !important;}"
          // ── кнопки ──
          + "input[type=submit],input[type=button],button,input.btn{background:#3A96D6 !important;"
          +   "color:#fff !important;border:none !important;border-radius:12px !important;"
          +   "min-height:46px !important;line-height:1.2 !important;padding:12px 20px !important;"
          +   "font-size:15px !important;font-weight:700 !important;cursor:pointer;"
          +   "font-family:-apple-system,sans-serif !important;margin:6px 0;}"
          + "input[type=checkbox],input[type=radio]{width:auto;min-height:0 !important;"
          +   "accent-color:#3A96D6;}";
          var st = document.createElement('style');
          st.id = 'interraTheme';
          st.textContent = css;
          document.head.appendChild(st);
        })();
      ''');
      if (dark) await _injectCabinetDark();
    } catch (_) {/* страница могла смениться - не критично */}
  }

  /// тёмная тема для страниц кабинета: перебиваем светлые значения из основной
  /// инъекции (фон, текст, поверхности). бренд-акценты и оранжевую рамку оставляем
  Future<void> _injectCabinetDark() async {
    await _controller.runJavaScript(r'''
      (function(){
        if(document.getElementById('interraDark')) return;
        var css = ""
        + "html,body{background:#0F141A !important;color:#EAEEF2 !important;}"
        // глушим ВСЕ белые поверхности сайта UTM (иначе кабинет остаётся белым):
        // атрибуты bgcolor, боковую панель, меню, обёртки контента
        + "[bgcolor]{background-color:transparent !important;}"
        + ".sidebar{background:transparent !important;border-right-color:#2C3742 !important;}"
        // на мобиле .header/.nav в utm7 имеют background:#fff - глушим
        + ".header{background-color:transparent !important;}"
        + ".nav{background-color:#131A22 !important;}"
        + ".nav-wrapper,.main,.grid,.wrapper,.b-content,#aaatds{background-color:transparent !important;}"
        + ".nav a,.nav-link{color:#C3CDD6 !important;}"
        // выбранная/наведённая вкладка меню была светлой (#f4f4f4)
        + ".nav-link.--active,.nav-link:hover{background-color:#1E2833 !important;}"
        + ".nav-link.--active{color:#5AB0EE !important;}"
        + ".nav-divider .divider{background:#2C3742 !important;border-color:#2C3742 !important;}"
        + ".nav-footer{border-top-color:#2C3742 !important;}"
        + ".nav-footer__note,.nav-footer__text,.header-logo__note,.font-s,.font-dark{color:#9BA8B4 !important;}"
        + ".header-burger__item{background:#C3CDD6 !important;}"
        + "font[color='black'],font[color='#000000'],font[color='#000']{color:#EAEEF2 !important;}"
        + "a{color:#5AB0EE !important;}"
        + "hr{border-top-color:#2C3742 !important;}"
        // информер: тёмная карточка, оранжевая рамка сохраняется
        + ".b-informer tr td{background:#241C13 !important;color:#E7D6C4 !important;}"
        + ".b-informer a,.b-informer a font{color:#F79B5B !important;}"
        // счёт
        + ".b-account tr{border-bottom-color:#26313C !important;}"
        + ".b-account td[align=right]{color:#8A97A2 !important;}"
        + ".b-account td:not([align=right]),.b-account span,.b-account td font{color:#EAEEF2 !important;}"
        // вкладки
        + ".b-tab{border-bottom-color:#2C3742 !important;}"
        + ".b-tab td.active,.b-tab td a{color:#9BA8B4 !important;}"
        + ".b-tab td.active{color:#EAEEF2 !important;}"
        // заголовки
        + ".t,.font-l,.font-dark{color:#EAEEF2 !important;}"
        // таблицы данных
        + "#aaatds table:not(.b-tab):not(.b-content):not(.b-account):not(.b-informer) td{border-bottom-color:#26313C !important;}"
        + "#aaatds table:not(.b-tab):not(.b-content):not(.b-account):not(.b-informer) th{color:#8A97A2 !important;}"
        + "#aaatds table:not(.b-tab):not(.b-content):not(.b-account):not(.b-informer) tr:nth-child(even) td{background:#151C24 !important;}"
        // поля и списки
        + "input:not([type=submit]):not([type=button]):not([type=checkbox]):not([type=radio]):not([type=hidden]),textarea,select{background:#19212A !important;color:#EAEEF2 !important;border-color:#2C3742 !important;}"
        // вход в раздел
        + ".login-title h2{color:#EAEEF2 !important;}"
        + "div.btn7{background:#1B242E !important;color:#9BA8B4 !important;}";
        var st = document.createElement('style');
        st.id = 'interraDark';
        st.textContent = css;
        document.head.appendChild(st);
      })();
    ''');
  }

  /// разбирает результат runJavaScriptReturningResult в Map. iOS отдаёт JSON-
  /// строку как есть, Android - в кавычках с экранированием (нужен повторный
  /// decode)
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

  /// если UTM5 уронил сессию и показал форму входа по паролю - токен-ссылка
  /// протухла; молча перезапрашиваем свежую через `cmd=open`
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
        // страница входа - переоткрываем со свежим токеном. защита от цикла:
        // повторно не входим, пока не загрузится нормальная (не-входная) страница
        if (!_recovering) {
          _recovering = true;
          _openCabinet();
        }
      } else {
        _recovering = false; // здоровая страница - снимаем защиту
      }
    } catch (_) {/* страница могла уже смениться - не критично */}
  }

  /// pull-to-refresh: в самом верху страницы тянем вниз - вся страница уезжает
  /// вниз, сверху появляется значок и поворачивается по мере вытягивания; за
  /// порогом он крутится непрерывно и кабинет перезагружается
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

  /// делает телефон в оранжевой карточке-информере (`.b-informer`) кликабельным:
  /// оборачивает номер в `<a href="tel:…">`, дальше тап перехватывает
  /// [_handleNavigation] и открывает системный набор. так номер можно не
  /// переписывать вручную. запускается на каждой загрузке, повторно безопасно
  Future<void> _linkifyInformerPhones() async {
    try {
      await _controller.runJavaScript(r'''
        (function(){
          var box = document.querySelector('.b-informer');
          if(!box || box.__telLinked) return;
          box.__telLinked = true;
          // +7/8, затем ещё 10 цифр через любые разделители (пробел, -, –, скобки)
          var re = /(?:\+7|8)[\s\-–()]*\d(?:[\s\-–()]*\d){9}/g;
          var walker = document.createTreeWalker(box, NodeFilter.SHOW_TEXT, null);
          var targets = [];
          while(walker.nextNode()){
            var n = walker.currentNode;
            // пропускаем то, что уже внутри ссылки
            if(n.parentNode && n.parentNode.closest && n.parentNode.closest('a')) continue;
            re.lastIndex = 0;
            if(re.test(n.nodeValue)) targets.push(n);
          }
          targets.forEach(function(n){
            re.lastIndex = 0;
            var html = n.nodeValue.replace(re, function(m){
              var d = m.replace(/\D/g,'');
              if(d.length !== 11) return m;           // не телефон - не трогаем
              if(d[0] === '8') d = '7' + d.slice(1);   // 8XXXXXXXXXX → 7XXXXXXXXXX
              return '<a href="tel:+' + d + '">' + m + '</a>';
            });
            if(html !== n.nodeValue){
              var span = document.createElement('span');
              span.innerHTML = html;
              n.parentNode.replaceChild(span, n);
            }
          });
        })();
      ''');
    } catch (_) {/* страница могла смениться - не критично */}
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
