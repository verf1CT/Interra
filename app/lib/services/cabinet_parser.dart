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

  @visibleForTesting
  static CabinetData parseCabinetHtml(String htmlString) {
    final doc = parser.parse(htmlString);
    _checkAuth(doc);

    // 1. Извлечение из DOM таблиц (.b-account или любые таблицы «ключ - значение»)
    String? foundFullName;
    String? foundAccount;
    String? foundTariff;
    double? foundBalance;

    final allRows = doc.querySelectorAll('tr');
    for (final tr in allRows) {
      final cells = tr.querySelectorAll('td, th');
      if (cells.length >= 2) {
        // Поддержка строк с 2, 4 или более столбцами (пары ключ-значение)
        for (int i = 0; i + 1 < cells.length; i += 2) {
          final key = cells[i].text.trim().toLowerCase();
          final val = cells[i + 1].text.trim();

          if (val.isNotEmpty) {
            if (foundFullName == null &&
                (key.contains('фио') ||
                    key.contains('абонент') ||
                    key.contains('клиент') ||
                    key.contains('владелец') ||
                    key.contains('плательщик') ||
                    key.contains('пользователь') ||
                    key.contains('лицо'))) {
              if (val.toLowerCase() != 'абонент' &&
                  val.toLowerCase() != 'клиент' &&
                  val.toLowerCase() != 'фио') {
                foundFullName = val;
              }
            }

            if (foundAccount == null &&
                (key.contains('счет') ||
                    key.contains('счёт') ||
                    key.contains('договор') ||
                    key.contains('аккаунт') ||
                    key.contains('лицевой') ||
                    key.contains('л/с') ||
                    key.contains('код'))) {
              final m = RegExp(r'([0-9]{3,})').firstMatch(val);
              if (m != null) {
                foundAccount = m.group(1);
              }
            }

            if (foundTariff == null &&
                (key.contains('тариф') ||
                    key.contains('услуга') ||
                    key.contains('пакет') ||
                    key.contains('план'))) {
              foundTariff = val;
            }

            if (foundBalance == null &&
                (key.contains('баланс') ||
                    key.contains('остаток') ||
                    key.contains('к оплате'))) {
              final m = RegExp(r'([−-]?[\d\s\u00A0]+(?:[.,]\d+)?)').firstMatch(val);
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

    final text = doc.body?.text ?? '';

    // 2. Баланс (если не найден в таблице)
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

    // 3. Счет / Договор (с поддержкой буквы «е» и «ё»)
    if (foundAccount == null) {
      final accountMatch = RegExp(
        r'(?:(?:Электронный|Лицевой|Основной)\s+)?(?:сч[её]т|л/?с|договор)(?:[а-яА-ЯёЁ\s№:]*?)([0-9]{3,})',
        caseSensitive: false,
      ).firstMatch(text);
      foundAccount = accountMatch?.group(1);
    }

    // 4. ФИО
    if (foundFullName == null) {
      final fioMatch = RegExp(
        r'(?:Полное\s+)?(?:ФИО|Ф\.И\.О\.)[\s:]*(.+?)(?=\n|<|\r|$|Тариф|Баланс|Лицевой)',
        caseSensitive: false,
      ).firstMatch(text) ??
      RegExp(
        r'(?:Абонент|Клиент|Плательщик)[\s:]*([А-ЯЁ][а-яё\-]+(?:[ \t\u00A0]+[А-ЯЁ][а-яё\-]+){1,2})',
      ).firstMatch(text);
      
      final matchedName = fioMatch?.group(1)?.trim();
      if (matchedName != null &&
          matchedName.isNotEmpty &&
          matchedName.toLowerCase() != 'абонент' &&
          matchedName.toLowerCase() != 'клиент') {
        foundFullName = matchedName;
      }
    }

    // 5. Тариф
    if (foundTariff == null) {
      final tariffMatch = RegExp(
        r'(?:Тарифный\s+план|Текущий\s+тариф|Тариф)[\s:]*(.+?)(?=\n|<|\r|$|Баланс|Лицевой|Основной|Счет|Счёт)',
        caseSensitive: false,
      ).firstMatch(text);
      foundTariff = tariffMatch?.group(1)?.trim();
    }

    return CabinetData(
      balance: foundBalance ?? 0.0,
      account: foundAccount ?? '',
      fullName: (foundFullName != null && foundFullName.isNotEmpty) ? foundFullName : 'Абонент',
      tariff: (foundTariff != null && foundTariff.isNotEmpty) ? foundTariff : 'Неизвестный тариф',
      rawHtml: htmlString,
    );
  }

  @visibleForTesting
  static List<PaymentItem> parsePaymentsHtml(String htmlString) {
    final doc = parser.parse(htmlString);
    _checkAuth(doc);
    
    List<PaymentItem> items = [];
    final tables = doc.querySelectorAll('table');
    for (var table in tables) {
      final rows = table.querySelectorAll('tr');
      if (rows.length < 2) continue;

      final headerText = rows[0].text.toLowerCase();
      if (headerText.contains('дата') && (headerText.contains('сумма') || headerText.contains('приход'))) {
        for (int i = 1; i < rows.length; i++) {
          final cells = rows[i].querySelectorAll('td');
          if (cells.length >= 2) {
            final date = cells[0].text.trim();
            final rawAmount = cells[1].text.trim().replaceAll('−', '-').replaceAll(RegExp(r'[\s\u00A0]'), '').replaceAll(',', '.');
            final amount = double.tryParse(rawAmount) ?? 0.0;
            final comment = cells.length > 2 ? cells[2].text.trim() : '';

            if (date.isNotEmpty) {
              items.add(PaymentItem(date: date, amount: amount, comment: comment));
            }
          }
        }
        break;
      }
    }
    return items;
  }

  @visibleForTesting
  static List<ServiceItem> parseServicesHtml(String htmlString) {
    final doc = parser.parse(htmlString);
    _checkAuth(doc);
    
    List<ServiceItem> items = [];
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
            String cost = '';
            String status = '';
            
            if (cells.length >= 3) {
              cost = cells[1].text.trim();
              status = cells[2].text.trim();
            } else {
              status = cells[1].text.trim();
            }
            
            if (name.isNotEmpty && !name.toLowerCase().contains('итого')) {
               items.add(ServiceItem(name: name, status: status, cost: cost));
            }
          }
        }
        break;
      }
    }
    return items;
  }

  static Future<CabinetData?> fetchCabinetData(String appToken) async {
    final htmlString = await _fetchHtml(appToken, oper: 'info');
    var data = parseCabinetHtml(htmlString);

    // Если тариф не указан на главной странице oper=info (в UTM5 тарифы часто лежат на oper=tariffs)
    if (data.tariff == 'Неизвестный тариф' || data.tariff.isEmpty) {
      try {
        final services = await fetchServices(appToken);
        if (services.isNotEmpty) {
          final active = services.firstWhere(
            (s) => s.status.toLowerCase().contains('актив') || s.status.toLowerCase().contains('подключ'),
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
