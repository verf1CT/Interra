import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import 'billing_api.dart';
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
  static Future<String> _fetchHtml(String appToken, {String oper = 'info'}) async {
    final r = await BillingApi.openCabinet(appToken);
    if (!r.isOk || r.data == null) {
      if (r.code == '0') throw Exception('auth_expired');
      throw Exception(r.networkError ? 'network_error' : 'Не удалось получить ссылку');
    }

    final liveUrl = AppConfig.cabinetUrl(r.data!, oper: oper);
    
    try {
      final res = await http.get(Uri.parse(liveUrl)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('network_error');

      return res.body;
    } catch (e) {
      debugPrint('CabinetParser fetch error: $e');
      throw Exception('network_error');
    }
  }

  static void _checkAuth(dom.Document doc) {
    if (doc.querySelector('input[name="pass"]') != null || 
        doc.querySelector('a[href*="oper=ident"]') != null) {
      throw Exception('auth_expired');
    }
  }

  @visibleForTesting
  static CabinetData parseCabinetHtml(String htmlString) {
    final doc = parser.parse(htmlString);
    _checkAuth(doc);
    
    final text = doc.body?.text ?? '';

    // Баланс
    final balanceMatch = RegExp(r'Баланс[\s:]*(-?[\d\s\u00A0]+(?:[.,]\d+)?)\s*руб').firstMatch(text);
    double balance = 0.0;
    if (balanceMatch != null) {
      final rawBalance = balanceMatch.group(1) ?? '0';
      final cleaned = rawBalance.replaceAll(RegExp(r'[\s\u00A0]'), '').replaceAll(',', '.');
      balance = double.tryParse(cleaned) ?? 0.0;
    }

    // Счет
    final accountMatch = RegExp(r'(?:Электронный|Лицевой)\s+счёт[\s:]*([0-9]{3,})').firstMatch(text);
    final account = accountMatch?.group(1) ?? '';

    // ФИО
    final fioMatch = RegExp(r'Полное ФИО[\s:]*(.+?)(?=\n|Тарифный)').firstMatch(text);
    final fullName = fioMatch?.group(1)?.trim() ?? 'Абонент';

    // Тариф
    final tariffMatch = RegExp(r'Тарифный план[\s:]*(.+?)(?=\n|Баланс|Лицевой)').firstMatch(text);
    final tariff = tariffMatch?.group(1)?.trim() ?? 'Неизвестный тариф';

    return CabinetData(
      balance: balance,
      account: account,
      fullName: fullName,
      tariff: tariff,
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
          if (cells.length >= 3) {
            final date = cells[0].text.trim();
            final rawAmount = cells[1].text.trim().replaceAll(RegExp(r'[\s\u00A0]'), '').replaceAll(',', '.');
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
    return parseCabinetHtml(htmlString);
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
