import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cabinet_parser.dart';

class DemoTariff {
  final String title;
  final String speed;
  final String price;
  final List<String> features;
  final bool isCurrent;
  final String? badge;

  const DemoTariff({
    required this.title,
    required this.speed,
    required this.price,
    required this.features,
    this.isCurrent = false,
    this.badge,
  });
}

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

  /// По умолчанию ВКЛЮЧЕН для этой сборки (сборка для скриншотов)
  static final ValueNotifier<bool> isEnabled = ValueNotifier<bool>(true);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_prefKey)) {
        isEnabled.value = prefs.getBool(_prefKey) ?? true;
      } else {
        isEnabled.value = true;
      }
    } catch (_) {
      isEnabled.value = true;
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
        account: '276997',
        fullName: 'Михаил Мешкой',
        tariff: 'Комфорт 200',
        address: 'ул. Хвойная, д. 5',
        login: '216997',
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

  static List<DemoTariff> get availableTariffs => const [
        DemoTariff(
          title: 'Базовый 100',
          speed: '100 Мбит/с',
          price: '550 ₽/мес',
          features: ['Безлимитный интернет', 'Оптический канал', 'Поддержка 24/7'],
          isCurrent: false,
        ),
        DemoTariff(
          title: 'Комфорт 200',
          speed: '200 Мбит/с',
          price: '750 ₽/мес',
          features: ['Сверхбыстрый интернет', '150+ каналов ТВ', 'Без ограничений по трафику'],
          isCurrent: true,
          badge: 'Ваш тариф',
        ),
        DemoTariff(
          title: 'Максимум 500',
          speed: '500 Мбит/с',
          price: '950 ₽/мес',
          features: ['Ультра-скорость для гейминга', '4K видео без буферизации', 'Wi-Fi 6 роутер'],
          isCurrent: false,
          badge: 'Хит продаж',
        ),
        DemoTariff(
          title: 'Гигабит 1000',
          speed: '1 Гбит/с',
          price: '1 200 ₽/мес',
          features: ['Максимальная скорость в городе', 'Выделенный статический IP', 'Премиум ТВ пакет'],
          isCurrent: false,
          badge: 'Премиум',
        ),
      ];

  static List<PaymentItem> get demoPayments => [
        PaymentItem(
          date: '28.10.2026 14:22',
          amount: 750.0,
          operation: 'СБП (Система быстрых платежей)',
          comment: 'Зачислено моментально',
          operator: 'СБП',
        ),
        PaymentItem(
          date: '01.10.2026 00:00',
          amount: -750.0,
          operation: 'Абонентская плата (Комфорт 200)',
          comment: 'Списание за октябрь',
          operator: 'SYSTEM',
        ),
        PaymentItem(
          date: '25.09.2026 19:10',
          amount: 750.0,
          operation: 'Банковская карта (SberPay)',
          comment: 'Автоплатёж',
          operator: 'СберБанк',
        ),
        PaymentItem(
          date: '01.09.2026 00:00',
          amount: -750.0,
          operation: 'Абонентская плата (Комфорт 200)',
          comment: 'Списание за сентябрь',
          operator: 'SYSTEM',
        ),
        PaymentItem(
          date: '20.08.2026 11:45',
          amount: 1000.0,
          operation: 'Система быстрых платежей',
          comment: 'Пополнение счёта',
          operator: 'СБП',
        ),
        PaymentItem(
          date: '01.08.2026 00:00',
          amount: -750.0,
          operation: 'Абонентская плата (Комфорт 200)',
          comment: 'Списание за август',
          operator: 'SYSTEM',
        ),
      ];

  static List<DemoSessionItem> get demoSessions => const [
        DemoSessionItem(
          ip: '178.46.128.45',
          startedAt: '30.10.2026 08:15',
          duration: '5 ч 30 мин',
          rxBytes: '24.6 ГБ',
          txBytes: '4.2 ГБ',
          isActive: true,
        ),
        DemoSessionItem(
          ip: '178.46.128.45',
          startedAt: '29.10.2026 00:00',
          duration: '23 ч 59 мин',
          rxBytes: '58.1 ГБ',
          txBytes: '8.7 ГБ',
          isActive: false,
        ),
        DemoSessionItem(
          ip: '178.46.128.45',
          startedAt: '28.10.2026 00:00',
          duration: '23 ч 59 мин',
          rxBytes: '42.3 ГБ',
          txBytes: '6.1 ГБ',
          isActive: false,
        ),
      ];
}
