import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cabinet_parser.dart';

class DemoSessionItem {
  final String ip;
  final String startedAt;
  final String duration;
  final String rxBytes;
  final String txBytes;
  final bool isActive;

  const DemoSessionItem({
    required this.ip,
    required this.startedAt,
    required this.duration,
    required this.rxBytes,
    required this.txBytes,
    this.isActive = false,
  });
}

/// Сервис демонстрационного режима для красивых скриншотов в App Store и Google Play.
/// Наполняет приложение идеальными, фотогеничными данными: баланс, активный тариф,
/// скорости, опции, история операций и сессии без предупреждений об ошибках.
class DemoMode {
  static const String _prefKey = 'demo_screenshot_mode_enabled';

  /// По умолчанию ВЫКЛЮЧЕН для продакшена
  static final ValueNotifier<bool> isEnabled = ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_prefKey)) {
        isEnabled.value = prefs.getBool(_prefKey) ?? false;
      } else {
        isEnabled.value = false;
      }
    } catch (_) {
      isEnabled.value = false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    isEnabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  static CabinetData get demoCabinetData => CabinetData(
        balance: 1250.00,
        account: '123456',
        fullName: 'Иванов Иван Иванович',
        tariff: 'Комфорт 200',
        address: 'г. Первоуральск, пр. Ильича, д. 15, кв. 42',
        login: '123456',
        needsPassportData: false,
        rawHtml: '',
      );

  static List<ServiceItem> get demoServices => [
        ServiceItem(
          name: 'Комфорт 200 (Безлимитный интернет 200 Мбит/с)',
          cost: '750 ₽ / мес',
          status: 'Активен',
        ),
        ServiceItem(
          name: 'Интерактивное ТВ «Базовое» (150+ телеканалов)',
          cost: 'Включено',
          status: 'Активно',
        ),
        ServiceItem(
          name: 'Умный домофон Интерра (видеокамера и архив)',
          cost: 'Включено',
          status: 'Активно',
        ),
      ];

  static List<PaymentItem> get demoPayments => [
        PaymentItem(
          date: '04.11.2026 14:22',
          amount: 750.0,
          operation: 'СБП (Система быстрых платежей)',
          comment: 'Зачислено моментально',
          operator: 'СБП',
        ),
        PaymentItem(
          date: '01.11.2026 00:00',
          amount: -750.0,
          operation: 'Абонентская плата (Комфорт 200)',
          comment: 'Списание за ноябрь',
          operator: 'SYSTEM',
        ),
        PaymentItem(
          date: '25.10.2026 19:10',
          amount: 750.0,
          operation: 'Банковская карта (SberPay)',
          comment: 'Автоплатёж',
          operator: 'СберБанк',
        ),
        PaymentItem(
          date: '01.10.2026 00:00',
          amount: -750.0,
          operation: 'Абонентская плата (Комфорт 200)',
          comment: 'Списание за октябрь',
          operator: 'SYSTEM',
        ),
        PaymentItem(
          date: '20.09.2026 11:45',
          amount: 1000.0,
          operation: 'Система быстрых платежей',
          comment: 'Пополнение счёта',
          operator: 'СБП',
        ),
        PaymentItem(
          date: '01.09.2026 00:00',
          amount: -750.0,
          operation: 'Абонентская плата (Комфорт 200)',
          comment: 'Списание за сентябрь',
          operator: 'SYSTEM',
        ),
      ];

  static List<DemoSessionItem> get demoSessions => const [
        DemoSessionItem(
          ip: '178.46.128.45',
          startedAt: '05.11.2026 08:15',
          duration: '5 ч 30 мин',
          rxBytes: '24.6 ГБ',
          txBytes: '4.2 ГБ',
          isActive: true,
        ),
        DemoSessionItem(
          ip: '178.46.128.45',
          startedAt: '04.11.2026 00:00',
          duration: '23 ч 59 мин',
          rxBytes: '58.1 ГБ',
          txBytes: '8.7 ГБ',
          isActive: false,
        ),
        DemoSessionItem(
          ip: '178.46.128.45',
          startedAt: '03.11.2026 00:00',
          duration: '23 ч 59 мин',
          rxBytes: '42.3 ГБ',
          txBytes: '6.1 ГБ',
          isActive: false,
        ),
      ];
}
