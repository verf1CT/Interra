import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cabinet_parser.dart';

/// Сервис демонстрационного режима для красивых скриншотов в App Store и Google Play.
/// Наполняет приложение идеальными, фотогеничными данными: баланс, активный тариф,
/// скорости, опции, история операций без предупреждений об ошибках.
class DemoMode {
  static const String _prefKey = 'qa_secret_demo_enabled_v2';
  static const String _legacyPrefKey = 'demo_screenshot_mode_enabled';

  /// По умолчанию ВЫКЛЮЧЕН для продакшена
  static final ValueNotifier<bool> isEnabled = ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_legacyPrefKey)) {
        await prefs.remove(_legacyPrefKey);
      }
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
        isRestricted: false,
        accounts: const [
          AccountOption(
            name: 'Иванов Иван Иванович',
            address: 'г. Первоуральск, пр. Ильича, д. 15, кв. 42',
            accountId: '123456',
            loginUrl: '',
          ),
          AccountOption(
            name: 'Иванов И.И. (Дача)',
            address: 'пос. Билимбай, ул. Ленина, д. 8',
            accountId: '654321',
            loginUrl: '',
          ),
        ],
        rawHtml: '',
        nextPaymentDate: DateTime(DateTime.now().year, DateTime.now().month + 1, 1),
        nextCharge: 750,
      );

  static TariffCatalog get demoTariffs => const TariffCatalog(
        current: 'Комфорт 200',
        groups: [
          TariffGroup(id: '1', name: '200 мегабит'),
          TariffGroup(
            id: '0',
            name: 'Нет тарифа',
            note: 'Нет тарифа - это состояние, при котором отсутствует доступ в Интернет и не снимается абонентская плата.',
          ),
        ],
        offers: {
          '1': [
            TariffOffer(
              name: 'Комфорт 200',
              price: 750,
              days: 30,
              details: ['Скорость доступа - до 200 Мбит/сек'],
            ),
            TariffOffer(
              name: 'Комфорт 200 на год',
              price: 7500,
              days: 365,
              perMonth: 625,
              details: [
                'Стоимость в перерасчёте на месяц - 625 рублей',
                'Экономия - 1500 руб.',
                'Скорость доступа - до 200 Мбит/сек',
              ],
            ),
          ],
          '0': [TariffOffer(name: 'Нет тарифа')],
        },
      );

  static TvInfo get demoTv => const TvInfo(
        login: '123456interra',
        password: '000000',
        premium: [
          TvPackage(name: 'Базовый', price: 200, href: ''),
          TvPackage(name: 'Расширенный', price: 300, href: ''),
          TvPackage(name: 'Максимальный', price: 800, href: ''),
          TvPackage(name: 'МАТЧ! ПРЕМЬЕР (Наш Футбол)', price: 299, extra: true, href: ''),
          TvPackage(name: 'Amediateka', price: 349, extra: true, href: ''),
        ],
        iptvFreeBase: true,
        iptv: [
          TvPackage(name: 'Полный', price: 200, note: '+128 каналов к Базовому пакету (итого 150)', href: ''),
        ],
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
}
