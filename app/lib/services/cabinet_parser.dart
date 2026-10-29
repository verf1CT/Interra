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
  final String rawHtml;

  CabinetData({
    required this.balance,
    required this.account,
    required this.fullName,
    required this.tariff,
    required this.rawHtml,
  });
}

class PaymentItem {
  final String date;
  final double amount;
  final String comment;

  PaymentItem({
    required this.date,
    required this.amount,
    required this.comment,
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

    // 4. Счет / Договор (с поддержкой буквы «е» и «ё»)
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

    // 5. ФИО через регулярное выражение
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

    // 6. Тариф через регулярное выражение с обязательным разделителем : или -
    if (foundTariff == null) {
      final tariffMatch = RegExp(
        r'(?:^|[\s\n\r>])(?:Тарифный\s+план|Текущий\s+тариф|Тариф)\s*[:\-]\s*(.+?)(?=\n|\r|<|$|Баланс|Лицевой|Основной|Счет|Счёт|ФИО)',
        caseSensitive: false,
      ).firstMatch(text);
      final rawT = tariffMatch?.group(1)?.trim();
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
        : 'Безлимитный интернет';

    return CabinetData(
      balance: foundBalance ?? 0.0,
      account: safeAccount,
      fullName: safeFullName,
      tariff: safeTariff,
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

      final headerText = rows[0].text.toLowerCase();
      if (headerText.contains('дата') &&
          (headerText.contains('сумма') ||
              headerText.contains('приход') ||
              headerText.contains('платеж') ||
              headerText.contains('расход'))) {
        for (int i = 1; i < rows.length; i++) {
          final cells = rows[i].querySelectorAll('td');
          if (cells.length >= 2) {
            final date = cells[0].text.trim();
            final rawAmount = cells[1]
                .text
                .trim()
                .replaceAll('−', '-')
                .replaceAll(RegExp(r'[\s\u00A0]'), '')
                .replaceAll(',', '.');
            final amount = double.tryParse(rawAmount) ?? 0.0;
            final comment = cells.length > 2 ? cells[2].text.trim() : '';

            if (date.isNotEmpty &&
                (date.contains('.') || date.contains('-') || date.contains('/'))) {
              items.add(PaymentItem(date: date, amount: amount, comment: comment));
            }
          }
        }
        if (items.isNotEmpty) break;
      }
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
    if (data.tariff == 'Безлимитный интернет' ||
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
          data = CabinetData(
            balance: data.balance,
            account: data.account,
            fullName: data.fullName,
            tariff: active.name,
            rawHtml: data.rawHtml,
          );
        }
      } catch (e) {
        debugPrint('CabinetParser fetchServices fallback error: $e');
      }
    }

    return data;
  }

  static Future<List<PaymentItem>> fetchPayments(String appToken) async {
    final htmlString = await _fetchHtml(appToken, oper: 'payments');
    return parsePaymentsHtml(htmlString);
  }

  static Future<List<ServiceItem>> fetchServices(String appToken) async {
    final htmlString = await _fetchHtml(appToken, oper: 'tariffs');
    return parseServicesHtml(htmlString);
  }
}
