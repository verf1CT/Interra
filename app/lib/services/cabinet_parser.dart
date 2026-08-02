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

      final doc = parser.parse(res.body);
      if (doc.querySelector('input[name="pass"]') != null || 
          doc.querySelector('a[href*="oper=ident"]') != null) {
        throw Exception('auth_expired');
      }

      return res.body;
    } catch (e) {
      debugPrint('CabinetParser fetch error: $e');
      throw Exception('network_error');
    }
  }

  /// Получение главной страницы ЛК
  static Future<CabinetData?> fetchCabinetData(String appToken) async {
    final htmlString = await _fetchHtml(appToken, oper: 'info');
    final doc = parser.parse(htmlString);
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

  /// Получение истории платежей
  static Future<List<PaymentItem>> fetchPayments(String appToken) async {
    final htmlString = await _fetchHtml(appToken, oper: 'payments');
    final doc = parser.parse(htmlString);
    
    List<PaymentItem> items = [];
    
    // Ищем таблицы, которые могут быть историей платежей. В UTM5 они часто имеют класс table_report или border=1
    final tables = doc.querySelectorAll('table');
    for (var table in tables) {
      final rows = table.querySelectorAll('tr');
      if (rows.length < 2) continue; // Нужен хотя бы заголовок и одна строка

      // Проверим, похож ли заголовок на таблицу платежей (Дата, Сумма)
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
        break; // Нашли нужную таблицу, выходим
      }
    }
    
    return items;
  }

  /// Получение услуг (доп. услуги, статус тарифа)
  static Future<List<ServiceItem>> fetchServices(String appToken) async {
    // В UTM5 список услуг обычно на oper=services или oper=tariffs
    // Попробуем oper=tariffs, там обычно висит таблица с услугами
    final htmlString = await _fetchHtml(appToken, oper: 'tariffs');
    final doc = parser.parse(htmlString);
    
    List<ServiceItem> items = [];
    
    final tables = doc.querySelectorAll('table');
    for (var table in tables) {
      final rows = table.querySelectorAll('tr');
      if (rows.length < 2) continue;

      final headerText = rows[0].text.toLowerCase();
      // Ищем заголовки вроде "Услуга", "Статус", "Абонентская плата"
      if (headerText.contains('услуг') || headerText.contains('тариф')) {
        for (int i = 1; i < rows.length; i++) {
          final cells = rows[i].querySelectorAll('td');
          if (cells.length >= 2) {
            final name = cells[0].text.trim();
            // В разных версиях UTM5 столбцы скачут, возьмем все остальные как статус/цену
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
}
