import 'dart:convert';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;
import 'billing_api.dart';
import 'secure_http.dart';
import '../config.dart';
import 'package:flutter/foundation.dart';

class CabinetData {
  final double balance;
  final String account;
  final String fullName;
  final String tariff;
  final String address;
  final String login;
  final bool needsPassportData;
  final String rawHtml;

  CabinetData({
    required this.balance,
    required this.account,
    required this.fullName,
    required this.tariff,
    this.address = '',
    this.login = '',
    this.needsPassportData = false,
    required this.rawHtml,
  });
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

  static Future<String> _fetchHtml(String appToken, {String oper = 'info'}) async {
    final r = await BillingApi.openCabinet(appToken);
    if (!r.isOk || r.data == null) {
      if (r.code == '0') throw Exception('auth_expired');
      throw Exception(r.networkError ? 'network_error' : 'Не удалось получить ссылку');
    }

    final liveUrl = AppConfig.cabinetUrl(r.data!, oper: oper);
    
    try {
      final res = await SecureHttp.get(Uri.parse(liveUrl)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('network_error');

      return decodeResponseBody(res.bodyBytes);
    } catch (e) {
      debugPrint('CabinetParser fetch error: $e');
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
                    key.contains('пакет') ||
                    key.contains('план'))) {
              if (!val.toLowerCase().contains('тарифы') &&
                  !val.contains('PremiumTV') &&
                  !val.contains('Пополнение') &&
                  !val.toLowerCase().contains('вход')) {
                foundTariff = val;
              }
            }

            // Баланс
            if (foundBalance == null &&
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

    final needsPassport = text.contains('Не хватает учётных данных') ||
        text.contains('ввести паспортные данные') ||
        safeTariff == 'Нет тарифа';

    return CabinetData(
      balance: foundBalance ?? 0.0,
      account: safeAccount,
      fullName: safeFullName,
      tariff: safeTariff,
      address: foundAddress ?? '',
      login: foundLogin ?? '',
      needsPassportData: needsPassport,
      rawHtml: htmlString,
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

  static Future<CabinetData?> fetchCabinetData(String appToken) async {
    final htmlString = await _fetchHtml(appToken, oper: 'info');
    var data = parseCabinetHtml(htmlString);

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
            data = CabinetData(
              balance: data.balance,
              account: data.account,
              fullName: data.fullName,
              tariff: active.name,
              address: data.address,
              login: data.login,
              needsPassportData: data.needsPassportData,
              rawHtml: data.rawHtml,
            );
          }
        }
      } catch (e) {
        debugPrint('CabinetParser fetchServices fallback error: $e');
      }
    }

    return data;
  }

  static Future<List<PaymentItem>> fetchPayments(String appToken) async {
    // Пробуем oper=reports (отчеты и операции за месяц), oper=payments, oper=operations
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
    final htmlString = await _fetchHtml(appToken, oper: 'tariffs');
    return parseServicesHtml(htmlString);
  }

  /// Активация карты экспресс-оплаты или сертификата
  static Future<bool> activateCertificate(String appToken, String code) async {
    final r = await BillingApi.openCabinet(appToken);
    if (!r.isOk || r.data == null) throw Exception('auth_expired');
    final liveUrl = AppConfig.cabinetUrl(r.data!, oper: 'cards');
    try {
      final res = await SecureHttp.post(
        Uri.parse(liveUrl),
        body: {'card_code': code, 'submit': '1'},
      ).timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Ссылка на веб-версию страницы с тарифами/паспортом с авторизованной сессией
  static Future<String?> getTariffsWebUrl(String appToken) async {
    try {
      final r = await BillingApi.openCabinet(appToken);
      if (!r.isOk || r.data == null) return null;
      return AppConfig.cabinetUrl(r.data!, oper: 'tariffs');
    } catch (_) {
      return null;
    }
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

    if (form != null) {
      // Hidden поля (login, oper, uid, session и др.)
      for (final el in form.querySelectorAll('input[type="hidden"]')) {
        final name = el.attributes['name'];
        if (name != null && name.isNotEmpty) {
          formData[name] = el.attributes['value'] ?? '';
        }
      }

      // Текстовые поля
      final textInputs = form.querySelectorAll(
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
      for (final el in form.querySelectorAll('input[type="checkbox"]')) {
        final name = el.attributes['name'];
        if (name != null && name.isNotEmpty) {
          formData[name] = el.attributes['value'] ?? '1';
        }
      }

      // Submit кнопка
      for (final el
          in form.querySelectorAll('input[type="submit"], button[type="submit"]')) {
        final name = el.attributes['name'];
        if (name != null && name.isNotEmpty) {
          formData[name] = el.attributes['value'] ?? '1';
        }
      }
    }

    // Всегда подстраховываемся базовыми именами параметров
    formData.putIfAbsent('passport', () => formattedPassport);
    formData.putIfAbsent('passport_date', () => formattedIssueDate);
    formData.putIfAbsent('passport_who', () => formattedIssuedBy);
    formData.putIfAbsent('birth_date', () => formattedBirthDate);
    formData.putIfAbsent('agreement', () => '1');
    formData.putIfAbsent('submit', () => '1');

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

    try {
      // 1. Загружаем текущую страницу oper=tariffs для разбора формы
      final getRes = await SecureHttp.get(Uri.parse(liveUrl))
          .timeout(const Duration(seconds: 15));
      if (getRes.statusCode != 200) throw Exception('network_error');

      final html = decodeResponseBody(getRes.bodyBytes);
      final doc = parser.parse(html);
      _checkAuth(doc);

      final form = doc.querySelector('form');
      Uri postUri = Uri.parse(liveUrl);
      if (form != null) {
        final formAction = form.attributes['action']?.trim();
        if (formAction != null && formAction.isNotEmpty) {
          postUri = postUri.resolve(formAction);
        }
      }

      final formData = buildPassportFormData(
        html,
        passport: passportSeriesNumber,
        issueDate: issueDate,
        issuedBy: issuedBy,
        birthDate: birthDate,
      );

      // 2. Отправляем заполненную форму
      final res = await SecureHttp.post(
        postUri,
        headers: {
          'Referer': liveUrl,
          'Origin': AppConfig.billingBase,
        },
        body: formData,
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200 && res.statusCode != 302 && res.statusCode != 303) {
        return false;
      }

      // 3. Проверяем, приняты ли данные сервером
      final responseBody = decodeResponseBody(res.bodyBytes);
      final ok = isPassportSavedSuccessfully(responseBody);
      if (!ok) {
        debugPrint('CabinetParser submitPassportData: server still requires passport');
      }
      return ok;
    } catch (e) {
      debugPrint('CabinetParser submitPassportData error: $e');
      return false;
    }
  }
}
