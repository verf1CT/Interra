import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;
import 'balance_store.dart';
import 'billing_api.dart';
import 'secure_http.dart';
import 'tv_data.dart';
import 'tariff_data.dart';
import 'block_data.dart';
export 'tv_data.dart';
export 'tariff_data.dart';
export 'block_data.dart';
import '../config.dart';
import '../utils/billing_math.dart';
import 'package:flutter/foundation.dart';

class AccountOption {
  final String name;
  final String address;
  final String accountId;
  final String loginUrl;

  const AccountOption({
    required this.name,
    this.address = '',
    this.accountId = '',
    required this.loginUrl,
  });
}

class CabinetData {
  final double balance;
  final String account;
  final String fullName;
  final String tariff;
  final String address;
  final String login;
  final bool needsPassportData;
  final bool isRestricted;
  final String? recommendedPayment;
  final List<AccountOption> accounts;
  final String rawHtml;

  /// «Следующий платёж до» и «Сумма к оплате» со страницы договора
  final DateTime? nextPaymentDate;
  final double? nextCharge;

  /// «Следующий тариф» со страницы договора: его биллинг показывает, когда
  /// абонент заказал смену; null - смена не заказана
  final String? nextTariff;

  CabinetData({
    required this.balance,
    required this.account,
    required this.fullName,
    required this.tariff,
    this.address = '',
    this.login = '',
    this.needsPassportData = false,
    this.isRestricted = false,
    this.recommendedPayment,
    this.accounts = const [],
    required this.rawHtml,
    this.nextPaymentDate,
    this.nextCharge,
    this.nextTariff,
  });

  CabinetData copyWith({
    String? account,
    String? fullName,
    String? tariff,
    String? address,
    List<AccountOption>? accounts,
  }) =>
      CabinetData(
        balance: balance,
        account: account ?? this.account,
        fullName: fullName ?? this.fullName,
        tariff: tariff ?? this.tariff,
        address: address ?? this.address,
        login: login,
        needsPassportData: needsPassportData,
        isRestricted: isRestricted,
        recommendedPayment: recommendedPayment,
        accounts: accounts ?? this.accounts,
        rawHtml: rawHtml,
        nextPaymentDate: nextPaymentDate,
        nextCharge: nextCharge,
        nextTariff: nextTariff,
      );
}

class PaymentItem {
  final String date;
  final double amount;
  final String operation;
  final String comment;
  final String operator;

  PaymentItem({
    required this.date,
    required this.amount,
    this.operation = '',
    this.comment = '',
    this.operator = '',
  });
}

class ServiceItem {
  final String name;
  final String status;
  final String cost;

  ServiceItem({
    required this.name,
    required this.status,
    required this.cost,
  });
}

class SmsSettings {
  final String phone;
  final bool enabled;
  final int? linkedApps;

  /// скрытые и текстовые поля формы как есть: отправляем их обратно
  final Map<String, String> fields;

  const SmsSettings({
    required this.phone,
    required this.enabled,
    this.linkedApps,
    this.fields = const {},
  });
}

class CabinetParser {
  /// Корректно декодирует ответ биллинга в UTF-8.
  /// Apache 2.2 на stat.interra.ru отдаёт заголовок `Content-Type: text/html`
  /// без явного указания `charset=utf-8`. По RFC 2616 Dart package:http
  /// по умолчанию декодирует тело как Latin-1 (ISO-8859-1), превращая кириллицу
  /// в кракозябры. Декодируем байты напрямую через utf8.decode.
  @visibleForTesting
  static String decodeResponseBody(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  /// ссылка `?login=…` выбранного договора, если у номера их несколько.
  /// null - работаем с договором по умолчанию (ссылка из `cmd=open`).
  /// от неё зависят все страницы кабинета: тариф, услуги, история
  static String? activeLogin;

  /// страница кабинета конкретного договора: берём из ссылки только значение
  /// `login=…` и грузим `aaainfo` (контент рендерит именно он), а не оболочку.
  /// если в строке нет `login=`, возвращает null
  @visibleForTesting
  static String? accountPageUrl(String href, {String oper = 'info'}) {
    final m = RegExp(r'login=([^&#\s]+)').firstMatch(href);
    if (m == null) return null;
    return AppConfig.cabinetUrl('?login=${m.group(1)}', oper: oper);
  }

  /// заглушки вместо имени, которые парсер подставляет сам
  static bool isPlaceholderName(String name) =>
      name.isEmpty || name == 'Абонент' || name.startsWith('Договор №');

  /// куки сессии кабинета. ссылка из `cmd=open` при первом заходе выдаёт куку,
  /// и без неё страницы конкретных договоров отвечают формой входа
  static String? _sessionCookie;

  /// токен сессии из навигации страницы договора. разделы кабинета (тарифы,
  /// отчёты) лежат в отдельных скриптах aaatarif и aaaotch и открываются
  /// только с ним: ссылка договора из списка одноразовая
  static String? _navToken;
  static Future<void>? _navLoading;

  static void resetSession() {
    activeLogin = null;
    _sessionCookie = null;
    _navToken = null;
    _navInfoHtml = null;
  }

  @visibleForTesting
  static String? extractNavToken(String html) =>
      RegExp(r'aaatarif\?login=([^&"\x27\s<>]+)').firstMatch(html)?.group(1);

  /// страница договора, с которой взят токен: из неё берём сумму ближайшего платежа
  static String? _navInfoHtml;

  static void _captureNavToken(String html) {
    final t = extractNavToken(html);
    if (t != null && t.isNotEmpty) {
      _navToken = t;
      _navInfoHtml = html;
    }
  }

  /// название действующего тарифа со страницы aaatarif; null - нет тарифа
  @visibleForTesting
  static String? parseCurrentTariff(String html) {
    final text = parser.parse(html).body?.text ?? '';
    final m = RegExp(r'Действующий\s+тариф:\s*([^\n\r]+)').firstMatch(text);
    final name = m?.group(1)?.trim();
    if (name == null || name.isEmpty || name.toLowerCase() == 'нет тарифа') return null;
    return name;
  }

  /// «Сумма к оплате» со страницы договора, в рублях
  @visibleForTesting
  static double? parseNextCharge(String html) {
    final text = parser.parse(html).body?.text.replaceAll('\u00A0', ' ') ?? '';
    final m = RegExp(r'Сумма\s+к\s+оплате\s*([0-9]+(?:[.,][0-9]+)?)').firstMatch(text);
    return m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', '.'));
  }

  static Future<void> _ensureNavToken(String appToken) async {
    if (_navToken != null) return;
    _navLoading ??= _fetchHtml(appToken)
        .then((_) {})
        .whenComplete(() => _navLoading = null);
    await _navLoading;
  }

  /// страница раздела кабинета выбранного договора, например
  /// aaatarif?oper=tarif или aaaotch?oper=otch. null - не удалось открыть
  /// [form] - поля формы раздела: тогда страница запрашивается POST, как её
  /// отправляет кнопка в браузере (login и oper подставляются сами)
  /// [query] - добавка к адресу, например `&xid=10`. [authInBody] = false -
  /// login и oper только в адресе, как у форм с action=""
  static Future<String?> _fetchSection(String appToken, String script, String oper,
      {Map<String, String>? form, String query = '', bool authInBody = true}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _ensureNavToken(appToken);
        final token = _navToken;
        if (token == null) return null;
        final url = Uri.parse('${AppConfig.billingBase}/$script?login=$token&oper=$oper$query');
        final res = await (form == null
                ? SecureHttp.get(url)
                : SecureHttp.post(url,
                    body: {if (authInBody) 'login': token, if (authInBody) 'oper': oper, ...form}))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) return null;
        final html = decodeResponseBody(res.bodyBytes);
        if (!_looksLoggedOut(html)) return html;
        _navToken = null;
      } catch (e) {
        if (e.toString().contains('auth_expired')) rethrow;
        debugPrint('CabinetParser section $script error: $e');
        return null;
      }
    }
    return null;
  }

  static void _rememberCookie(http.Response res) {
    final fresh = _extractCookieHeader(res.headers['set-cookie']);
    if (fresh == null || fresh.isEmpty) return;
    final jar = <String, String>{};
    for (final pair in '${_sessionCookie ?? ''}; $fresh'.split(';')) {
      final i = pair.indexOf('=');
      if (i > 0) jar[pair.substring(0, i).trim()] = pair.substring(i + 1).trim();
    }
    _sessionCookie = jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  static bool _looksLoggedOut(String html) =>
      html.contains('login-control') && !html.contains('b-account');

  /// открывает кабинет по свежей ссылке и запоминает куку сессии
  static Future<String> _openDefaultPage(String appToken, String oper) async {
    final r = await BillingApi.openCabinet(appToken);
    if (!r.isOk || r.data == null) {
      if (r.code == '0') throw Exception('auth_expired');
      throw Exception(r.networkError ? 'network_error' : 'Не удалось получить ссылку');
    }
    final res = await SecureHttp.get(Uri.parse(AppConfig.cabinetUrl(r.data!, oper: oper)))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('network_error');
    _rememberCookie(res);
    return decodeResponseBody(res.bodyBytes);
  }

  /// постоянная часть ссылки договора: без последнего куска после точки,
  /// который меняется при каждой выдаче списка
  @visibleForTesting
  static String linkKey(String href) {
    final v = RegExp(r'login=([^&#\s]+)').firstMatch(href)?.group(1) ?? href;
    final i = v.lastIndexOf('.');
    return i > 0 && v.indexOf('.') != i ? v.substring(0, i) : v;
  }

  static String? _findFreshLink(List<AccountOption> accounts, String staleHref) {
    final want = linkKey(staleHref);
    for (final a in accounts) {
      if (linkKey(a.loginUrl) == want) return a.loginUrl;
    }
    return null;
  }

  static Future<String> _fetchHtml(String appToken, {String oper = 'info', String? directUrl}) async {
    final html = await _loadHtml(appToken, oper: oper, directUrl: directUrl);
    _captureNavToken(html);
    return html;
  }

  static Future<String> _loadHtml(String appToken, {String oper = 'info', String? directUrl}) async {
    final explicit = directUrl != null && directUrl.isNotEmpty ? directUrl : activeLogin;
    final contractUrl = explicit != null ? accountPageUrl(explicit, oper: oper) : null;

    try {
      if (contractUrl == null) {
        if (directUrl != null && directUrl.isNotEmpty) {
          final base = AppConfig.billingBase;
          final liveUrl = directUrl.startsWith('http')
              ? directUrl
              : (directUrl.startsWith('/') ? '$base$directUrl' : '$base/$directUrl');
          final res = await SecureHttp.get(Uri.parse(liveUrl)).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) throw Exception('network_error');
          return decodeResponseBody(res.bodyBytes);
        }
        return await _openDefaultPage(appToken, oper);
      }

      // страница договора. ссылки из списка живут недолго: если биллинг
      // ответил формой входа, берём свежий список и ищем в нём тот же договор
      var url = contractUrl;
      for (var attempt = 0; attempt < 2; attempt++) {
        final res = await SecureHttp.get(
          Uri.parse(url),
          headers: {if (_sessionCookie != null) 'Cookie': _sessionCookie!},
        ).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) throw Exception('network_error');
        _rememberCookie(res);
        final html = decodeResponseBody(res.bodyBytes);
        if (!_looksLoggedOut(html) || attempt == 1) return html;

        final listHtml = await _openDefaultPage(appToken, 'info');
        final fresh = _findFreshLink(parseCabinetHtml(listHtml).accounts, explicit!);
        if (fresh == null) return html;
        if (activeLogin == explicit) activeLogin = fresh;
        url = accountPageUrl(fresh, oper: oper)!;
      }
      throw Exception('network_error');
    } catch (e) {
      debugPrint('CabinetParser fetch error: $e');
      if (e.toString().contains('auth_expired')) throw Exception('auth_expired');
      throw Exception('network_error');
    }
  }

  static void _checkAuth(dom.Document doc) {
    if (doc.querySelector('input[type="password"]') != null ||
        doc.querySelector('input[name="pass"]') != null ||
        (doc.querySelector('.login-control') != null && doc.querySelector('.b-account') == null)) {
      throw Exception('auth_expired');
    }
  }

  static bool _isValidName(String s) {
    if (s.length < 2 || s.length > 70) return false;
    final lower = s.toLowerCase();
    if (lower == 'абонент' ||
        lower == 'клиент' ||
        lower == 'фио' ||
        lower == 'лицо' ||
        lower == 'физическое лицо' ||
        lower == 'юридическое лицо' ||
        lower == 'пользователь') {
      return false;
    }
    // Исключаем строки, содержащие телефонные префиксы, ссылки, адреса или служебный текст
    if (s.contains('800') ||
        lower.contains('тел') ||
        lower.contains('звонок') ||
        lower.contains('http') ||
        lower.contains('://') ||
        lower.contains('.ru') ||
        lower.contains('ул.') ||
        lower.contains('помощь') ||
        lower.contains('центр') ||
        lower.contains('обслуживан') ||
        lower.contains('отдел')) {
      return false;
    }
    return true;
  }

  @visibleForTesting
  static CabinetData parseCabinetHtml(String htmlString) {
    final doc = parser.parse(htmlString);
    _checkAuth(doc);

    // Удаляем из DOM блоки навигации, шапки, сайдбара и информер контактов (.b-informer),
    // чтобы их служебные телефоны (8-800) и адреса офисов не путались с данными абонента.
    doc
        .querySelectorAll(
            '.b-informer, .b-tab, .sidebar, .nav, .header, .login, #parent_bunny')
        .forEach((e) => e.remove());

    String? foundFullName;
    String? foundAccount;
    String? foundTariff;
    String? foundAddress;
    String? foundLogin;
    double? foundBalance;
    DateTime? foundNextDate;
    double? foundNextCharge;
    String? foundNextTariff;

    // 1. Приоритетно ищем в таблице .b-account (основная таблица абонента в UTM5)
    final accountTable = doc.querySelector('.b-account');
    final rowsToScan = accountTable != null
        ? accountTable.querySelectorAll('tr')
        : doc.querySelectorAll('tr');

    for (final tr in rowsToScan) {
      final cells = tr.querySelectorAll('td, th');
      if (cells.length >= 2) {
        // Поддержка строк с 2, 4 или более столбцами (пары ключ-значение)
        for (int i = 0; i + 1 < cells.length; i += 2) {
          final key = cells[i].text.trim().toLowerCase();
          final val = cells[i + 1].text.trim();

          if (val.isNotEmpty) {
            // ФИО абонента
            if (foundFullName == null &&
                (key.contains('фио') ||
                    key == 'абонент' ||
                    key == 'абонент:' ||
                    key == 'клиент' ||
                    key == 'клиент:' ||
                    key.contains('полное имя') ||
                    key.contains('имя абонента') ||
                    key.contains('владелец') ||
                    key.contains('плательщик') ||
                    key.contains('контактное лицо'))) {
              if (_isValidName(val)) {
                foundFullName = val;
              }
            }

            // Номер лицевого счёта / договора
            if (foundAccount == null &&
                (key.contains('лицевой') ||
                    key.contains('основной счет') ||
                    key.contains('основной счёт') ||
                    key.contains('счет:') ||
                    key.contains('счёт:') ||
                    key.contains('договор') ||
                    key == 'л/с' ||
                    key == 'л/с:' ||
                    key.contains('код абонента') ||
                    key.contains('аккаунт'))) {
              final m = RegExp(r'([0-9]{3,})').firstMatch(val);
              if (m != null && m.group(1) != '800' && m.group(1) != '7700010') {
                foundAccount = m.group(1);
              }
            }

            // Адрес абонента / подключения
            if (foundAddress == null &&
                (key.contains('адрес') ||
                    key.contains('место установки') ||
                    key.contains('подключение') ||
                    key == 'адрес:')) {
              if (val.length >= 3 && !val.contains('8-800') && !val.contains('Трубников')) {
                foundAddress = val;
              }
            }

            // Тарифный план
            if (foundTariff == null &&
                (key == 'тариф' ||
                    key == 'тариф:' ||
                    key.contains('тарифный план') ||
                    key.contains('текущий тариф') ||
                    key.contains('действующий тариф') ||
                    key.contains('пакет') ||
                    key.contains('план'))) {
              if (!val.toLowerCase().contains('тарифы') &&
                  !val.contains('PremiumTV') &&
                  !val.contains('Пополнение') &&
                  !val.toLowerCase().contains('вход')) {
                foundTariff = val;
              }
            }

            // заказанная смена тарифа: «Квартал+Неделя 100М  подробнее»
            if (key.contains('следующий тариф')) {
              final t = val.replaceAll(RegExp(r'\s*подробнее\s*$', caseSensitive: false), '').trim();
              if (t.isNotEmpty) foundNextTariff ??= t;
            }

            // ближайшее списание
            if (key.contains('следующий платёж') || key.contains('следующий платеж')) {
              foundNextDate ??= parseBillingDate(val);
            }
            if (key.contains('сумма к оплате')) {
              final m = RegExp(r'([0-9]+(?:[.,][0-9]+)?)').firstMatch(val.replaceAll(RegExp(r'[\s ]'), ''));
              foundNextCharge ??= m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', '.'));
            }

            // Баланс
            if (foundBalance == null &&
                !key.contains('сумма к оплате') &&
                (key.contains('баланс') ||
                    key.contains('остаток') ||
                    key.contains('к оплате'))) {
              final m =
                  RegExp(r'([−-]?[\d\s\u00A0]+(?:[.,]\d+)?)').firstMatch(val);
              if (m != null) {
                final cleaned = m
                    .group(1)!
                    .replaceAll('−', '-')
                    .replaceAll(RegExp(r'[\s\u00A0]'), '')
                    .replaceAll(',', '.');
                foundBalance = double.tryParse(cleaned);
              }
            }
          }
        }
      }
    }

    // 2. Проверяем таблицу тарифов table.tlt (Tarif List Table в UTM5)
    if (foundTariff == null) {
      final tlt = doc.querySelector('table.tlt');
      if (tlt != null) {
        for (final tr in tlt.querySelectorAll('tr')) {
          final cells = tr.querySelectorAll('td, th');
          if (cells.isNotEmpty) {
            final tName = cells[0].text.trim();
            if (tName.isNotEmpty &&
                !tName.toLowerCase().contains('тариф') &&
                !tName.toLowerCase().contains('итого') &&
                !tName.contains('PremiumTV') &&
                !tName.contains('Пополнение')) {
              foundTariff = tName;
              break;
            }
          }
        }
      }
    }

    final text = doc.body?.text ?? '';

    // 3. Баланс (если не найден в таблице)
    if (foundBalance == null) {
      final balanceMatch = RegExp(
        r'(?:Основной\s+|Текущий\s+)?(?:Баланс|Остаток)(?:[\s\wа-яА-ЯёЁ]+)?[\s:]*([−-]?[\d\s\u00A0]+(?:[.,]\d+)?)\s*(?:руб\.?|₽|р\.?)?',
        caseSensitive: false,
      ).firstMatch(text);
      if (balanceMatch != null) {
        final rawBalance = balanceMatch.group(1) ?? '0';
        final cleaned = rawBalance
            .replaceAll('−', '-')
            .replaceAll(RegExp(r'[\s\u00A0]'), '')
            .replaceAll(',', '.');
        foundBalance = double.tryParse(cleaned);
      }
    }

    // 4. Счет / Договор
    if (foundAccount == null) {
      final syspayAcc = RegExp(
        r'Ваш\s+лицевой\s+счет(?:[^\d\n\r]*?)–?\s*([0-9]{3,})',
        caseSensitive: false,
      ).firstMatch(text);
      if (syspayAcc != null) {
        final a = syspayAcc.group(1);
        if (a != null && a != '800' && a != '7700010') {
          foundAccount = a;
        }
      }
    }

    if (foundAccount == null) {
      final accountMatch = RegExp(
        r'(?:(?:Электронный|Лицевой|Основной)\s+)?(?:сч[её]т|л/?с|договор)(?:[а-яА-ЯёЁ\s№:]*?)([0-9]{3,})',
        caseSensitive: false,
      ).firstMatch(text);
      final acc = accountMatch?.group(1);
      if (acc != null && acc != '800' && acc != '7700010') {
        foundAccount = acc;
      }
    }

    // 5. Обработка формата "Клиент: Имя Фамилия (АДРЕС / ЛОГИН)"
    final clientWithAddress = RegExp(
      r'Клиент:\s*([^(<\n\r]+?)(?:\s*\((.+)\))?(?:\n|<|$)',
      caseSensitive: false,
    ).firstMatch(text);
    if (clientWithAddress != null) {
      final namePart = clientWithAddress.group(1)?.trim();
      final paren = clientWithAddress.group(2)?.trim();
      if (foundFullName == null && namePart != null && _isValidName(namePart)) {
        foundFullName = namePart;
      }
      if (paren != null && paren.isNotEmpty) {
        if (paren.contains('/')) {
          final idx = paren.lastIndexOf('/');
          final addrPart = paren.substring(0, idx).trim();
          final loginPart = paren.substring(idx + 1).trim();
          if (foundAddress == null && addrPart.isNotEmpty) {
            foundAddress = addrPart;
          }
          if (loginPart.isNotEmpty) {
            foundLogin = loginPart;
          }
        } else {
          foundAddress ??= paren;
        }
      }
    }

    // 6. ФИО через регулярное выражение
    if (foundFullName == null) {
      final fioMatch = RegExp(
        r'(?:^|[\s\n\r>])(?:Полное\s+)?(?:ФИО|Ф\.И\.О\.)\s*[:\-]\s*(.+?)(?=\n|\r|<|$|Тариф|Баланс|Лицевой|Основной|Счет|Счёт)',
        caseSensitive: false,
      ).firstMatch(text) ??
      RegExp(
        r'(?:^|[\s\n\r>])(?:Абонент|Клиент|Плательщик)\s*[:\-]\s*(.+?)(?=\n|\r|<|$|Тариф|Баланс|Лицевой|Основной|Счет|Счёт)',
        caseSensitive: false,
      ).firstMatch(text);
      
      final matchedName = fioMatch?.group(1)?.trim();
      if (matchedName != null && _isValidName(matchedName)) {
        foundFullName = matchedName;
      }
    }

    // 7. Адрес через регулярное выражение
    if (foundAddress == null) {
      final addrMatch = RegExp(
        r'(?:^|[\s\n\r>])(?:Адрес\s+подключения|Адрес\s+установки|Адрес)\s*[:\-]\s*(.+?)(?=\n|\r|<|$|Тариф|Баланс|Лицевой|Договор|Клиент)',
        caseSensitive: false,
      ).firstMatch(text);
      final a = addrMatch?.group(1)?.trim();
      if (a != null && a.length >= 3 && !a.contains('8-800') && !a.contains('Трубников')) {
        foundAddress = a;
      }
    }

    // 8. Тариф через регулярное выражение
    if (foundTariff == null) {
      final activeTariffMatch = RegExp(
        r'(?:^|[\s\n\r>])(?:Действующий\s+тариф|Текущий\s+тариф|Тарифный\s+план|Тариф)\s*[:\-]\s*(.+?)(?=\n|\r|<|$|Баланс|Лицевой|Основной|Счет|Счёт|Клиент|Не\s+хватает)',
        caseSensitive: false,
      ).firstMatch(text);
      final rawT = activeTariffMatch?.group(1)?.trim();
      if (rawT != null &&
          !rawT.toLowerCase().contains('тарифы') &&
          !rawT.contains('PremiumTV') &&
          !rawT.contains('Пополнение')) {
        foundTariff = rawT;
      }
    }

    final safeAccount = foundAccount ?? '';
    final safeFullName = (foundFullName != null && _isValidName(foundFullName))
        ? foundFullName
        : (safeAccount.isNotEmpty ? 'Договор № $safeAccount' : 'Абонент');
    final safeTariff = (foundTariff != null && foundTariff.isNotEmpty)
        ? foundTariff
        : 'Нет тарифа';

    // ограничение - только когда биллинг пишет об этом сам: минус на балансе
    // ещё не значит, что услуги выключены
    final isRestricted = text.contains('Услуги связи ограничены') ||
        text.contains('отключен до пополнения') ||
        text.toLowerCase().contains('услуги ограничены');

    final recommendedPayment = RegExp(
      r'Рекомендуемая\s+сумма\s+(?:платежа)?[:\-]?\s*([0-9\s]+(?:[.,][0-9]+)?\s*(?:руб\.?|₽|р\.?)?)',
      caseSensitive: false,
    ).firstMatch(text)?.group(1)?.trim();

    final List<AccountOption> parsedAccounts = [];
    final allLinks = doc.querySelectorAll('a');
    for (final a in allLinks) {
      final href = a.attributes['href'] ?? '';
      final t = a.text.trim();
      if ((href.contains('login=') || href.contains('aaainfo')) &&
          t.isNotEmpty &&
          !t.toLowerCase().contains('выход') &&
          !t.toLowerCase().contains('назад') &&
          !t.toLowerCase().contains('главная') &&
          !t.toLowerCase().contains('тариф')) {
        String name = t;
        String addr = '';
        if (t.contains('(') && t.endsWith(')')) {
          final idx = t.indexOf('(');
          name = t.substring(0, idx).trim();
          addr = t.substring(idx + 1, t.length - 1).trim();
        }
        final accMatch = RegExp(r'([0-9]{4,})').firstMatch(href) ?? RegExp(r'([0-9]{4,})').firstMatch(t);
        parsedAccounts.add(AccountOption(
          name: name,
          address: addr,
          accountId: accMatch?.group(1) ?? '',
          loginUrl: href,
        ));
      }
    }

    final needsPassport = text.contains('Не хватает учётных данных') ||
        text.contains('ввести паспортные данные') ||
        (text.contains('паспортные данные') && text.contains('выбора тарифа'));

    return CabinetData(
      balance: foundBalance ?? 0.0,
      account: safeAccount,
      fullName: safeFullName,
      tariff: safeTariff,
      address: foundAddress ?? '',
      login: foundLogin ?? '',
      needsPassportData: needsPassport,
      isRestricted: isRestricted,
      recommendedPayment: recommendedPayment,
      accounts: parsedAccounts,
      rawHtml: htmlString,
      nextPaymentDate: foundNextDate,
      nextCharge: foundNextCharge,
      nextTariff: foundNextTariff,
    );
  }

  @visibleForTesting
  static List<PaymentItem> parsePaymentsHtml(String htmlString) {
    final doc = parser.parse(htmlString);
    _checkAuth(doc);
    doc
        .querySelectorAll(
            '.b-informer, .b-tab, .sidebar, .nav, .header, .login, #parent_bunny')
        .forEach((e) => e.remove());
    
    List<PaymentItem> items = [];
    final tables = doc.querySelectorAll('table');
    for (var table in tables) {
      if (table.querySelector('table') != null) continue;
      final rows = table.querySelectorAll('tr');
      if (rows.length < 2) continue;

      int headerRowIdx = -1;
      List<String> headers = [];
      for (int i = 0; i < rows.length && i < 3; i++) {
        final rowCells = rows[i].querySelectorAll('th, td');
        final txt = rows[i].text.toLowerCase();
        if (txt.contains('выполнено') ||
            txt.contains('дата') ||
            txt.contains('операция') ||
            txt.contains('сумма') ||
            txt.contains('приход') ||
            txt.contains('платеж') ||
            txt.contains('расход')) {
          headerRowIdx = i;
          headers = rowCells.map((c) => c.text.trim().toLowerCase()).toList();
          break;
        }
      }

      if (headerRowIdx == -1) continue;

      int dateCol = headers.indexWhere((h) => h.contains('выполнено') || h.contains('дата') || h.contains('время'));
      if (dateCol == -1) dateCol = 0;
      int operatorCol = headers.indexWhere((h) => h.contains('оператор'));
      int operationCol = headers.indexWhere((h) => h.contains('операция') || h.contains('тип'));
      int amountCol = headers.indexWhere((h) => h.contains('сумма') || h.contains('приход') || h.contains('расход') || h.contains('платеж'));
      int commentCol = headers.indexWhere((h) => h.contains('комментарий') || h.contains('примечание'));

      for (int i = headerRowIdx + 1; i < rows.length; i++) {
        final cells = rows[i].querySelectorAll('td');
        if (cells.length < 2) continue;

        final date = (dateCol >= 0 && dateCol < cells.length) ? cells[dateCol].text.trim() : '';
        final op = (operationCol >= 0 && operationCol < cells.length) ? cells[operationCol].text.trim() : '';
        final operName = (operatorCol >= 0 && operatorCol < cells.length) ? cells[operatorCol].text.trim() : '';
        final comm = (commentCol >= 0 && commentCol < cells.length) ? cells[commentCol].text.trim() : '';

        double amount = 0.0;
        if (amountCol >= 0 && amountCol < cells.length) {
          final rawAmount = cells[amountCol]
              .text
              .trim()
              .replaceAll('−', '-')
              .replaceAll(RegExp(r'[\s\u00A0]'), '')
              .replaceAll(',', '.');
          amount = double.tryParse(rawAmount) ?? 0.0;
        } else if (cells.length >= 2) {
          final rawAmount = cells[1]
              .text
              .trim()
              .replaceAll('−', '-')
              .replaceAll(RegExp(r'[\s\u00A0]'), '')
              .replaceAll(',', '.');
          amount = double.tryParse(rawAmount) ?? 0.0;
        }

        if (date.isNotEmpty &&
            (date.contains('.') || date.contains('-') || date.contains('/'))) {
          items.add(PaymentItem(
            date: date,
            amount: amount,
            operation: op,
            operator: operName,
            comment: comm.isNotEmpty ? comm : op,
          ));
        }
      }
      if (items.isNotEmpty) break;
    }
    return items;
  }

  @visibleForTesting
  static List<ServiceItem> parseServicesHtml(String htmlString) {
    final doc = parser.parse(htmlString);
    _checkAuth(doc);
    doc
        .querySelectorAll(
            '.b-informer, .b-tab, .sidebar, .nav, .header, .login, #parent_bunny')
        .forEach((e) => e.remove());
    
    List<ServiceItem> items = [];

    // 1. Проверяем table.tlt
    final tltTables = doc.querySelectorAll('table.tlt');
    for (final tlt in tltTables) {
      final rows = tlt.querySelectorAll('tr');
      for (final r in rows) {
        final cells = r.querySelectorAll('td');
        if (cells.isNotEmpty) {
          final name = cells[0].text.trim();
          if (name.isNotEmpty &&
              !name.toLowerCase().contains('тариф') &&
              !name.toLowerCase().contains('итого') &&
              !name.contains('PremiumTV') &&
              !name.contains('Пополнение') &&
              !name.toLowerCase().contains('вход')) {
            final cost = cells.length > 1 ? cells[1].text.trim() : '';
            final status = cells.length > 2 ? cells[2].text.trim() : 'Активна';
            items.add(ServiceItem(name: name, status: status, cost: cost));
          }
        }
      }
    }
    if (items.isNotEmpty) return items;

    // 2. Ищем другие таблицы
    final tables = doc.querySelectorAll('table');
    for (var table in tables) {
      final rows = table.querySelectorAll('tr');
      if (rows.length < 2) continue;

      final headerText = rows[0].text.toLowerCase();
      if (headerText.contains('услуг') || headerText.contains('тариф')) {
        for (int i = 1; i < rows.length; i++) {
          final cells = rows[i].querySelectorAll('td');
          if (cells.length >= 2) {
            final name = cells[0].text.trim();
            if (name.isEmpty ||
                name.toLowerCase().contains('итого') ||
                name.contains('PremiumTV') ||
                name.contains('Пополнение') ||
                name.toLowerCase().contains('вход') ||
                name.toLowerCase() == 'тарифы') {
              continue;
            }
            String cost = '';
            String status = '';
            
            if (cells.length >= 3) {
              cost = cells[1].text.trim();
              status = cells[2].text.trim();
            } else {
              status = cells[1].text.trim();
            }
            
            items.add(ServiceItem(name: name, status: status, cost: cost));
          }
        }
        if (items.isNotEmpty) break;
      }
    }
    return items;
  }

  /// номер лицевого счёта и адрес для строки из списка выбора.
  /// в ссылке `?login=…` лежит внутренний логин биллинга, а не номер, и адреса
  /// в списке нет, поэтому открываем страницу самого счёта. пустые строки - не нашли
  static Future<({String number, String address})> fetchPayAccount(
      String appToken, String loginUrl) async {
    try {
      final d = parseCabinetHtml(await _fetchHtml(appToken, directUrl: loginUrl));
      return (number: d.account, address: d.address);
    } catch (e) {
      debugPrint('fetchPayAccount error: $e');
      return (number: '', address: '');
    }
  }

  /// страница без шума: скрипты, стили, картинки и подвал выкидываем, пробелы
  /// схлопываем, длинные страницы режем. остаётся то, по чему работает парсер
  static String _slimHtml(String html) {
    final doc = parser.parse(html);
    doc
        .querySelectorAll(
            'script, style, noscript, svg, img, link, meta, head, iframe, .sidebar, [class*="nav-footer"], footer')
        .forEach((e) => e.remove());
    var body = (doc.body?.outerHtml ?? html)
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'>\s+<'), '>\n<');
    const limit = 15000;
    if (body.length > limit) {
      body = '${body.substring(0, limit)}\n...[обрезано, всего ${body.length}]';
    }
    return body;
  }

  /// сырые страницы кабинета для разбора вёрстки: список договоров и страницы
  /// выбранного (главная и тарифы). нужны, чтобы чинить разбор по настоящему
  /// HTML, а не по догадкам. заголовок каждой страницы - адрес запроса
  static Future<String> collectDebugDump(String appToken) async {
    final out = StringBuffer();
    Future<void> add(String title, Future<String> Function() load) async {
      out.writeln('\n===== $title =====');
      try {
        out.writeln(_slimHtml(await load()));
      } catch (e) {
        out.writeln('ОШИБКА: $e');
      }
    }

    Future<String> raw(String url) async {
      final res = await SecureHttp.get(
        Uri.parse(url),
        headers: {if (_sessionCookie != null) 'Cookie': _sessionCookie!},
      ).timeout(const Duration(seconds: 15));
      _rememberCookie(res);
      return decodeResponseBody(res.bodyBytes);
    }

    final saved = activeLogin;
    out.writeln('activeLogin: $saved');
    final smsReply = lastSmsResponse;
    if (smsReply != null) await add('ответ на отправку sms-формы', () async => smsReply);
    final tariffReply = lastTariffResponse;
    if (tariffReply != null) await add('ответ на заказ тарифа', () async => tariffReply);
    final blockReply = lastBlockResponse;
    if (blockReply != null) await add('ответ на кнопку блокировки', () async => blockReply);
    // ссылка из списка одноразовая: для каждого договора берём список заново
    for (var i = 0; i < 2; i++) {
      var listHtml = '';
      if (i == 0) {
        await add('список договоров', () async => listHtml = await _openDefaultPage(appToken, 'info'));
      } else {
        try {
          listHtml = await _openDefaultPage(appToken, 'info');
        } catch (e) {
          out.writeln('ОШИБКА списка: $e');
        }
      }
      final accounts = listHtml.isEmpty ? <AccountOption>[] : parseCabinetHtml(listHtml).accounts;
      if (accounts.length <= i) break;
      final n = i + 1;
      final info = accountPageUrl(accounts[i].loginUrl);
      if (info == null) continue;
      _navToken = null;
      try {
        final html = await raw(info);
        _captureNavToken(html);
        // здесь же биллинг показывает заказанные операции, например следующий тариф
        if (i == 0) await add('основная информация, договор 1', () async => html);
        out.writeln('\nдоговор $n, oper=info: ${_looksLoggedOut(html) ? 'форма входа' : 'открылся'}, '
            'токен раздела: ${_navToken != null ? 'есть' : 'нет'}');
      } catch (e) {
        out.writeln('\nдоговор $n, oper=info: ОШИБКА $e');
      }
      final tok = _navToken;
      if (tok == null) continue;
      // страницы с формами: по ним делаем sms, сертификаты и блокировку
      for (final (script, oper, title) in const [
        ('aaasmssvc', 'smssvc', 'sms-уведомления'),
        ('aaasyspays', 'syspays', 'сертификаты'),
        ('aaaprcn', 'prcn', 'блокировка'),
        ('aaaiptv', 'iptvm', 'iptv, пакеты'),
        ('aaaxtvpsm', 'xtvpsmm', 'premiumtv, пакеты'),
        // страницы одного пакета: там видно, как подключать и как помечен подключённый
        ('aaaxtvpsm', 'xtvpsmm&xid=10', 'premiumtv, пакет Базовый'),
        ('aaaxtvpsm', 'xtvpsmm&xid=22', 'premiumtv, доп. пакет'),
        ('aaaiptv', 'iptvm&xid=1', 'iptv, пакет Полный'),
      ]) {
        await add('$title ($script)', () => raw('${AppConfig.billingBase}/$script?login=$tok&oper=$oper'));
      }
      // тарифы: список групп, сами группы и страница действующего тарифа.
      // открываем только действующий: если переход по ссылке сам заказывает
      // тариф, то заказ того же тарифа ничего не меняет (он и так продлится)
      var tarif = '';
      await add('тарифы (aaatarif)',
          () async => tarif = await raw('${AppConfig.billingBase}/aaatarif?login=$tok&oper=tarif'));
      final current = parseCurrentTariff(tarif);
      for (final g in parseTariffGroups(tarif).take(4)) {
        var page = '';
        await add('тарифы, группа ${g.id}', () async => page = await raw(
            '${AppConfig.billingBase}/aaatarif?login=$tok&oper=tarif&gro=${g.id}'));
        for (final o in parseTariffOffers(page).where((o) => current != null && o.name == current).take(1)) {
          await add('тарифы, страница действующего тарифа (pack=${o.pack})', () => raw(tariffWebUrl(o)));
        }
      }
      break;
    }
    _navToken = null;

    // login=... - это сессия абонента: подменяем значение номером по порядку
    // появления и оставляем форму (цифры -> 0, буквы -> a)
    final seen = <String, int>{};
    String mask(String v) {
      final n = seen.putIfAbsent(v, () => seen.length + 1);
      final shape = v.replaceAll(RegExp(r'\d'), '0').replaceAll(RegExp(r'[A-Za-z]'), 'a');
      return 'TOKEN$n($shape)';
    }

    return out
        .toString()
        .replaceAllMapped(RegExp(r'login=([^&"\x27\s<>]+)'),
            (m) => m.group(1)!.isEmpty ? 'login=' : 'login=${mask(m.group(1)!)}')
        // тот же токен лежит в скрытых полях форм
        .replaceAllMapped(RegExp(r'value="([A-Za-z]\.\d+\.\d+)"'), (m) => 'value="${mask(m.group(1)!)}"')
        // пароль от Premium TV в дамп не нужен, хватит формы разметки
        .replaceAllMapped(RegExp(r'(пароль:\s*(?:<[^>]*>\s*)*)([^<\s]+)', caseSensitive: false),
            (m) => '${m.group(1)}***');
  }

  /// [targetUrl] - ссылка выбранного договора. без неё грузим договор по
  /// умолчанию, а если номер ведёт на страницу выбора - первый из списка
  static Future<CabinetData?> fetchCabinetData(String appToken, {String? targetUrl}) async {
    _navToken = null;
    if (targetUrl != null) {
      activeLogin = targetUrl;
    } else {
      activeLogin = null;
    }
    final htmlString = await _fetchHtml(appToken, oper: 'info', directUrl: targetUrl);
    var data = parseCabinetHtml(htmlString);

    // на странице выбранного договора ссылки навигации тоже содержат login=,
    // поэтому «первый договор» подставляем только для страницы выбора
    if (targetUrl == null && data.account.isEmpty && data.accounts.isNotEmpty) {
      try {
        final first = data.accounts.first;
        activeLogin = first.loginUrl;
        final subHtml = await _fetchHtml(appToken, directUrl: first.loginUrl);
        final subData = parseCabinetHtml(subHtml);
        data = subData.copyWith(
          account: subData.account.isNotEmpty ? subData.account : first.accountId,
          fullName: !isPlaceholderName(subData.fullName) ? subData.fullName : first.name,
          address: subData.address.isNotEmpty ? subData.address : first.address,
          accounts: data.accounts,
        );
      } catch (e) {
        activeLogin = null;
        debugPrint('Auto-load first account error: $e');
      }
    }

    // Если тариф не указан на главной странице oper=info (в UTM5 тарифы часто лежат на oper=tariffs)
    if (data.tariff == 'Нет тарифа' ||
        data.tariff == 'Неизвестный тариф' ||
        data.tariff.isEmpty) {
      try {
        final services = await fetchServices(appToken);
        if (services.isNotEmpty) {
          final active = services.firstWhere(
            (s) =>
                s.status.toLowerCase().contains('актив') ||
                s.status.toLowerCase().contains('подключ') ||
                s.status.toLowerCase().contains('включ'),
            orElse: () => services.first,
          );
          if (active.name.isNotEmpty && !active.name.toLowerCase().contains('нет тарифа')) {
            data = data.copyWith(tariff: active.name);
          }
        }
      } catch (e) {
        debugPrint('CabinetParser fetchServices fallback error: $e');
      }
    }

    return data;
  }

  /// самый ранний год, за который биллинг отдаёт отчёты (список «год» в форме
  /// страницы операций). null - форму не видели, прошлые месяцы не листаем
  static int? reportsFromYear;

  @visibleForTesting
  static int? parseReportsFromYear(String html) {
    final years = parser
        .parse(html)
        .querySelectorAll('select[name="god"] option')
        .map((o) => int.tryParse(o.attributes['value'] ?? ''))
        .whereType<int>();
    return years.isEmpty ? null : years.reduce((a, b) => a < b ? a : b);
  }

  /// операции за конкретный месяц: та же форма «год / месяц» на странице отчётов
  static Future<List<PaymentItem>> fetchPaymentsMonth(String appToken, int year, int month) async {
    final html = await _fetchSection(appToken, 'aaaotch', 'otch',
        form: {'work': 'cost', 'god': '$year', 'mes': '$month'});
    if (html == null) throw Exception('network_error');
    return parsePaymentsHtml(html);
  }

  static Future<List<PaymentItem>> fetchPayments(String appToken) async {
    final section = await _fetchSection(appToken, 'aaaotch', 'otch');
    if (section != null) {
      reportsFromYear = parseReportsFromYear(section);
      final list = parsePaymentsHtml(section);
      if (list.isNotEmpty) return list;
      if (reportsFromYear != null) return const [];
    }
    // старый путь: так открывался единственный договор
    for (final op in ['reports', 'payments', 'operations']) {
      try {
        final html = await _fetchHtml(appToken, oper: op);
        final list = parsePaymentsHtml(html);
        if (list.isNotEmpty) return list;
      } catch (e) {
        debugPrint('fetchPayments ($op) error: $e');
      }
    }
    return [];
  }

  static Future<List<ServiceItem>> fetchServices(String appToken) async {
    final section = await _fetchSection(appToken, 'aaatarif', 'tarif');
    if (section != null) {
      final list = parseServicesHtml(section);
      if (list.isNotEmpty) return list;
      // таблицы услуг на странице нет, есть только название тарифа;
      // цену берём из «Суммы к оплате» страницы договора
      final name = parseCurrentTariff(section);
      if (name != null) {
        final info = _navInfoHtml;
        final charge = info == null ? null : parseNextCharge(info);
        final monthly = name.toLowerCase().contains('месяц');
        final cost = charge == null
            ? ''
            : '${BalanceStore.format(charge)}${monthly ? ' / мес' : ''}';
        // статуса у тарифа на странице нет: «действующий» уже сказано заголовком
        return [ServiceItem(name: name, status: '', cost: cost)];
      }
    }
    try {
      final htmlString = await _fetchHtml(appToken, oper: 'tariffs');
      return parseServicesHtml(htmlString);
    } catch (e) {
      if (section != null) return const [];
      rethrow;
    }
  }

  /// страница «смс-уведомления» (aaasmssvc): номер, галочка «присылать
  /// уведомления» и счётчик привязанных приложений. null - страница не открылась
  /// или формы на ней нет
  @visibleForTesting
  static SmsSettings? parseSmsSettings(String html) {
    final doc = parser.parse(html);
    final form = doc.querySelector('form#clkform') ?? doc.querySelector('form');
    if (form == null || form.querySelector('input[name="sendme"]') == null) return null;
    final apps = int.tryParse(
        RegExp(r'привязано\s+приложений:\s*(\d+)').firstMatch(doc.body?.text ?? '')?.group(1) ?? '');
    return SmsSettings(
      phone: form.querySelector('input[name="phone"]')?.attributes['value']?.trim() ?? '',
      enabled: form.querySelector('input[name="sendme"]')!.attributes.containsKey('checked'),
      linkedApps: apps,
      fields: {
        for (final el in form.querySelectorAll('input[type="hidden"], input[type="text"]'))
          if ((el.attributes['name'] ?? '').isNotEmpty) el.attributes['name']!: el.attributes['value'] ?? '',
      },
    );
  }

  static Future<SmsSettings?> fetchSmsSettings(String appToken) async {
    final html = await _fetchSection(appToken, 'aaasmssvc', 'smssvc');
    return html == null ? null : parseSmsSettings(html);
  }

  /// отправляет форму sms-уведомлений как кнопка «внести изменения».
  /// галочки браузер шлёт только отмеченными, так же делаем и мы. возвращает
  /// состояние страницы после отправки - по нему видно, принял ли биллинг
  /// ответ биллинга на последнюю отправку sms-формы: после неё приходит
  /// SMS-код, и как его вводить, видно только по этой странице. идёт в дамп
  static String? lastSmsResponse;

  /// биллинг ответил, что отправил код подтверждения
  static bool smsCodeRequested(String? html) {
    if (html == null) return false;
    final t = (parser.parse(html).body?.text ?? '').toLowerCase();
    return t.contains('код') && !t.contains('позволит вам входить');
  }

  static Future<SmsSettings?> saveSmsSettings(
    String appToken,
    SmsSettings current, {
    required bool enabled,
    bool unlinkApps = false,
  }) async {
    final form = <String, String>{
      ...current.fields,
      if (enabled) 'sendme': 'on',
      if (unlinkApps) 'delapp': 'on',
      'set': 'внести изменения',
    }
      ..remove('login')
      ..remove('oper');
    lastSmsResponse = await _fetchSection(appToken, 'aaasmssvc', 'smssvc', form: form);
    // ответ на POST может быть другой страницей, поэтому перечитываем
    return fetchSmsSettings(appToken);
  }

  /// форма для кода подтверждения в ответе на sms-форму: после «внести
  /// изменения» биллинг шлёт одноразовый код и ждёт его. null - поля для кода нет
  static BlockAction? smsCodeForm(String? html) => html == null
      ? null
      : parseBlockPage(html)
          .expand((s) => s.actions)
          // поле номера телефона в обычной форме - не код
          .where((a) => a.needsCode && a.codeField != 'phone')
          .firstOrNull;

  /// после отправки sms-формы биллинг ждёт код: есть поле для него или текст про код
  static bool smsCodeAsked(String? html) => smsCodeForm(html) != null || smsCodeRequested(html);

  /// отправляет код в форму из ответа и перечитывает настройки
  static Future<SmsSettings?> submitSmsCode(String appToken, BlockAction form, String code) async {
    lastSmsResponse = await _fetchSection(appToken, 'aaasmssvc', 'smssvc',
        form: {...form.fields, form.codeField!: code}, authInBody: false);
    return fetchSmsSettings(appToken);
  }

  /// страницы пакетов Premium TV и IPTV выбранного договора. ни одна не
  /// открылась - бросаем ошибку, чтобы экран показал «повторить»
  static Future<TvInfo> fetchTv(String appToken) async {
    final r = await Future.wait([
      _fetchSection(appToken, 'aaaxtvpsm', 'xtvpsmm'),
      _fetchSection(appToken, 'aaaiptv', 'iptvm'),
    ]);
    final premium = r[0], iptv = r[1];
    if (premium == null && iptv == null) throw Exception('network_error');
    final (login, password) = premium == null ? (null, null) : parsePremiumCredentials(premium);
    return TvInfo(
      login: login,
      password: password,
      premium: premium == null ? const [] : parseTvPackages(premium),
      iptvFreeBase: iptv != null && parseIptvFreeBase(iptv),
      iptv: iptv == null ? const [] : parseTvPackages(iptv),
    );
  }

  /// oper и xid из ссылки пакета (`?login=…&oper=xtvpsmm&xid=10`)
  static (String, String)? _packageRef(String href) {
    final q = Uri.splitQueryString(
        (href.startsWith('?') ? href.substring(1) : href).replaceAll('&amp;', '&'));
    final oper = q['oper'], xid = q['xid'];
    if (oper == null || xid == null) return null;
    return (oper, xid);
  }

  static Future<TvPackageDetails?> fetchTvPackage(String appToken, String script, String href) async {
    final ref = _packageRef(href);
    if (ref == null) return null;
    final html = await _fetchSection(appToken, script, ref.$1, query: '&xid=${ref.$2}');
    return html == null ? null : parseTvPackageDetails(html);
  }

  /// жмёт «включить этот пакет» и перечитывает страницу пакета: по ней видно,
  /// принял ли биллинг. списание с баланса делает сам биллинг
  static Future<TvPackageDetails?> enableTvPackage(
      String appToken, String script, String href, TvPackageDetails details) async {
    final ref = _packageRef(href);
    if (ref == null || !details.canEnable) return null;
    await _fetchSection(appToken, script, ref.$1,
        query: '&xid=${ref.$2}', form: details.form, authInBody: false);
    return fetchTvPackage(appToken, script, href);
  }

  /// группы тарифов и тарифы внутри них для выбранного счёта. null - раздел
  /// не открылся; группа, которая не загрузилась, остаётся без тарифов
  static Future<TariffCatalog?> fetchTariffs(String appToken) async {
    final main = await _fetchSection(appToken, 'aaatarif', 'tarif');
    if (main == null) return null;
    final groups = parseTariffGroups(main);
    final offers = <String, List<TariffOffer>>{};
    await Future.wait([
      for (final g in groups)
        _fetchSection(appToken, 'aaatarif', 'tarif', query: '&gro=${g.id}').then((h) {
          if (h != null) offers[g.id] = parseTariffOffers(h);
        }),
    ]);
    // заказанную смену страница тарифов не показывает, только страница договора
    final info = _navInfoHtml;
    String? next;
    try {
      next = info == null ? null : parseCabinetHtml(info).nextTariff;
    } catch (_) {}
    return TariffCatalog(current: parseCurrentTariff(main), groups: groups, offers: offers, next: next);
  }

  static String _offerQuery(TariffOffer o) {
    final gro = RegExp(r'gro=(\d+)').firstMatch(o.href)?.group(1);
    return '${gro == null ? '' : '&gro=$gro'}&pack=${o.pack}';
  }

  /// страница подтверждения тарифа: дата переключения и форма. null - не открылась
  static Future<TariffOrderPage?> fetchTariffOrder(String appToken, TariffOffer offer) async {
    if (offer.pack == null) return null;
    final html = await _fetchSection(appToken, 'aaatarif', 'tarif', query: _offerQuery(offer));
    return html == null ? null : parseTariffOrderPage(html);
  }

  /// ответ биллинга на последний заказ тарифа - уходит в дамп, чтобы видеть,
  /// как биллинг подтверждает выбор
  static String? lastTariffResponse;

  /// нажимает «ДА» на странице подтверждения. true - биллинг принял выбор
  static Future<bool> orderTariff(String appToken, TariffOffer offer, TariffOrderPage page) async {
    if (!page.canOrder) return false;
    final html = await _fetchSection(appToken, 'aaatarif', 'tarif',
        query: _offerQuery(offer), form: {...page.form, 'set': 'ДА'}, authInBody: false);
    lastTariffResponse = html;
    return tariffOrderAccepted(html);
  }

  /// страница тарифа в браузере: ссылка из группы относительная (`?login=…`)
  static String tariffWebUrl(TariffOffer offer) =>
      '${AppConfig.billingBase}/aaatarif${offer.href.startsWith('?') ? '' : '?'}${offer.href}';

  /// ссылка на раздел тарифов выбранного договора для браузера. токен сессии
  /// не привязан к кукам, поэтому открывается и вне приложения. если токена
  /// нет - старая ссылка cmd=open (у номера с одним договором это его страница)
  /// страница блокировки выбранного счёта (aaaprcn). null - не открылась
  static Future<String?> fetchBlockPage(String appToken) =>
      _fetchSection(appToken, 'aaaprcn', 'prcn');

  /// ответ биллинга на последнюю кнопку блокировки - уходит в дамп
  static String? lastBlockResponse;

  /// жмёт кнопку формы блокировки. у форм action="" или «?login=…&oper=prcn»,
  /// то есть тот же адрес раздела, поэтому login и oper только в адресе
  static Future<String?> submitBlockAction(String appToken, BlockAction action, {String? code}) async {
    final html = await _fetchSection(appToken, 'aaaprcn', 'prcn',
        form: {
          ...action.fields,
          if (action.codeField != null && code != null) action.codeField!: code,
        },
        authInBody: false);
    lastBlockResponse = html;
    return html;
  }

  static Future<String?> getTariffsWebUrl(String appToken) async {
    try {
      await _ensureNavToken(appToken);
      final token = _navToken;
      if (token != null) return '${AppConfig.billingBase}/aaatarif?login=$token&oper=tarif';
      final r = await BillingApi.openCabinet(appToken);
      if (!r.isOk || r.data == null) return null;
      return AppConfig.cabinetUrl(r.data!, oper: 'info');
    } catch (_) {
      return null;
    }
  }

  /// Извлекает Cookie-пары из заголовка `set-cookie`
  static String? _extractCookieHeader(String? setCookie) {
    if (setCookie == null || setCookie.isEmpty) return null;
    final parts = setCookie.split(RegExp(r',(?=[^;]+?=)'));
    final cookiePairs = <String>[];
    for (final part in parts) {
      final firstSection = part.split(';').first.trim();
      if (firstSection.contains('=')) {
        cookiePairs.add(firstSection);
      }
    }
    return cookiePairs.isNotEmpty
        ? cookiePairs.join('; ')
        : setCookie.split(';').first.trim();
  }

  /// Парсит HTML формы ввода паспорта и собирает Map параметров для отправки в биллинг
  @visibleForTesting
  static Map<String, String> buildPassportFormData(
    String html, {
    required String passport,
    required String issueDate,
    required String issuedBy,
    required String birthDate,
  }) {
    // 10 цифр паспорта приводим к формату СССС-НННННН
    final digitsOnly = passport.replaceAll(RegExp(r'\D'), '');
    final formattedPassport = (digitsOnly.length == 10)
        ? '${digitsOnly.substring(0, 4)}-${digitsOnly.substring(4)}'
        : passport.trim();

    final formattedIssueDate =
        issueDate.trim().replaceAll('/', '.').replaceAll('-', '.');
    final formattedBirthDate =
        birthDate.trim().replaceAll('/', '.').replaceAll('-', '.');
    final formattedIssuedBy = issuedBy.trim();

    final doc = parser.parse(html);
    final form = doc.querySelector('form');
    final Map<String, String> formData = {};

    // Ищем поля внутри формы или по всему документу (если в разметке UTM5 нарушена вложенность)
    final contextElement = form ?? doc.body ?? doc;

    for (final el in contextElement.querySelectorAll('input[type="hidden"]')) {
      final name = el.attributes['name'];
      if (name != null && name.isNotEmpty) {
        formData[name] = el.attributes['value'] ?? '';
      }
    }

    final textInputs = contextElement.querySelectorAll(
      'input[type="text"], input[type="tel"], input[type="number"], input:not([type])',
    );

    final values = [
      formattedPassport,
      formattedIssueDate,
      formattedIssuedBy,
      formattedBirthDate,
    ];

    for (var i = 0; i < textInputs.length; i++) {
      final input = textInputs[i];
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;

      final nameLower = name.toLowerCase();
      if (nameLower.contains('birth') ||
          nameLower.contains('rojd') ||
          nameLower.contains('born')) {
        formData[name] = formattedBirthDate;
      } else if (nameLower.contains('issue') ||
          nameLower.contains('vidan') ||
          nameLower.contains('kogda')) {
        formData[name] = formattedIssueDate;
      } else if (nameLower.contains('who') ||
          nameLower.contains('kem') ||
          nameLower.contains('org')) {
        formData[name] = formattedIssuedBy;
      } else if (nameLower.contains('pass') ||
          nameLower.contains('ser') ||
          (nameLower.contains('num') && !nameLower.contains('date'))) {
        formData[name] = formattedPassport;
      } else if (nameLower.contains('date')) {
        formData[name] = (i == 3) ? formattedBirthDate : formattedIssueDate;
      } else if (i < values.length) {
        formData[name] = values[i];
      }
    }

    // Чекбокс согласия
    for (final el in contextElement.querySelectorAll('input[type="checkbox"]')) {
      final name = el.attributes['name'];
      if (name != null && name.isNotEmpty) {
        formData[name] = el.attributes['value'] ?? '1';
      }
    }

    // Submit кнопка
    for (final el in contextElement
        .querySelectorAll('input[type="submit"], button[type="submit"]')) {
      final name = el.attributes['name'];
      if (name != null && name.isNotEmpty) {
        formData[name] = el.attributes['value'] ?? 'записать данные';
      }
    }

    // Всегда подстраховываемся всеми известными именами полей UTM5
    formData.putIfAbsent('doc_num', () => formattedPassport);
    formData.putIfAbsent('passport', () => formattedPassport);
    formData.putIfAbsent('doc_date', () => formattedIssueDate);
    formData.putIfAbsent('passport_date', () => formattedIssueDate);
    formData.putIfAbsent('doc_org', () => formattedIssuedBy);
    formData.putIfAbsent('passport_who', () => formattedIssuedBy);
    formData.putIfAbsent('birth_date', () => formattedBirthDate);
    formData.putIfAbsent('agreement', () => '1');
    formData.putIfAbsent('agree', () => '1');
    formData.putIfAbsent('submit', () => 'записать данные');
    formData.putIfAbsent('save', () => 'записать данные');
    formData.putIfAbsent('oper', () => 'tariffs');

    return formData;
  }

  /// Проверяет по HTML ответа биллинга, сохранились ли паспортные данные
  @visibleForTesting
  static bool isPassportSavedSuccessfully(String responseHtml) {
    if (responseHtml.trim().isEmpty) return false;
    final stillMissing = responseHtml.contains('Не хватает учётных данных') ||
        responseHtml.contains('ввести паспортные данные') ||
        responseHtml.contains('Для выбора тарифа необходимо ввести');
    return !stillMissing;
  }

  /// Отправка паспортных данных для выбора тарифа
  static Future<bool> submitPassportData({
    required String appToken,
    required String passportSeriesNumber,
    required String issueDate,
    required String issuedBy,
    required String birthDate,
  }) async {
    final r = await BillingApi.openCabinet(appToken);
    if (!r.isOk || r.data == null) throw Exception('auth_expired');

    final liveUrl = AppConfig.cabinetUrl(r.data!, oper: 'tariffs');
    final infoUrl = AppConfig.cabinetUrl(r.data!, oper: 'info');

    try {
      // 1. Инициализируем сессию через oper=info (в UTM5 куки авторизации рождаются здесь)
      String? sessionCookie;
      try {
        final infoRes = await SecureHttp.get(Uri.parse(infoUrl))
            .timeout(const Duration(seconds: 15));
        sessionCookie = _extractCookieHeader(infoRes.headers['set-cookie']);
      } catch (e) {
        debugPrint('CabinetParser init session error: $e');
      }

      // 2. Загружаем текущую страницу oper=tariffs для разбора формы
      final getRes = await SecureHttp.get(
        Uri.parse(liveUrl),
      ).timeout(const Duration(seconds: 15));
      if (getRes.statusCode != 200) throw Exception('network_error');

      // Обновляем куки, если пришли свежие
      final tariffsCookie = _extractCookieHeader(getRes.headers['set-cookie']);
      if (tariffsCookie != null && tariffsCookie.isNotEmpty) {
        sessionCookie = sessionCookie != null
            ? '$sessionCookie; $tariffsCookie'
            : tariffsCookie;
      }

      final html = decodeResponseBody(getRes.bodyBytes);
      final doc = parser.parse(html);
      _checkAuth(doc);

      final form = doc.querySelector('form');
      final originalUri = Uri.parse(liveUrl);
      Uri postUri = originalUri;
      if (form != null) {
        final formAction = form.attributes['action']?.trim();
        if (formAction != null && formAction.isNotEmpty) {
          final resolved = originalUri.resolve(formAction);
          // СОХРАНЯЕМ параметры (?login=...&oper=tariffs), иначе resolve('aaainfo')
          // отсекает query string и запрос становится анонимным!
          final queryParams =
              Map<String, String>.from(originalUri.queryParameters);
          queryParams.addAll(resolved.queryParameters);
          postUri = resolved.replace(queryParameters: queryParams);
        }
      }

      final formData = buildPassportFormData(
        html,
        passport: passportSeriesNumber,
        issueDate: issueDate,
        issuedBy: issuedBy,
        birthDate: birthDate,
      );

      // Дублируем login и oper в тело POST
      if (originalUri.queryParameters.containsKey('login')) {
        formData['login'] = originalUri.queryParameters['login']!;
      }
      formData['oper'] = 'tariffs';

      // 3. Отправляем заполненную форму с queryParams, Referer и Cookie
      final headers = {
        'Referer': liveUrl,
        'Origin': AppConfig.billingBase,
        if (sessionCookie != null && sessionCookie.isNotEmpty)
          'Cookie': sessionCookie,
      };

      final res = await SecureHttp.post(
        postUri,
        headers: headers,
        body: formData,
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200 && res.statusCode != 302 && res.statusCode != 303) {
        return false;
      }

      // 4. Проверяем, приняты ли данные сервером
      final responseBody = decodeResponseBody(res.bodyBytes);
      final ok = isPassportSavedSuccessfully(responseBody);
      if (!ok) {
        debugPrint(
            'CabinetParser submitPassportData: server still requires passport');
      }
      return ok;
    } catch (e) {
      debugPrint('CabinetParser submitPassportData error: $e');
      return false;
    }
  }
}
