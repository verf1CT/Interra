import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'balance_store.dart';
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
        tariff: 'Месяц 100М',
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
        nextPaymentDate: DateTime.now().add(const Duration(days: 18)),
        nextCharge: 1200,
      );

  // тарифы и описания - как на настоящей странице aaatarif
  static TariffCatalog get demoTariffs => const TariffCatalog(
        current: 'Месяц 100М',
        groups: [
          TariffGroup(id: '18', name: '100 мегабит'),
          TariffGroup(
            id: '0',
            name: 'Нет тарифа',
            note: 'Нет тарифа - это состояние, при котором отсутствует доступ в Интернет и не снимается абонентская плата.',
          ),
        ],
        offers: {
          '18': [
            TariffOffer(
              name: 'Месяц 100М',
              price: 1200,
              days: 30,
              details: ['Скорость доступа - до 100 Мбит/сек'],
            ),
            TariffOffer(
              name: 'Квартал+Неделя 100М',
              price: 3600,
              days: 98,
              perMonth: 1114,
              details: [
                'В подарок - одна неделя бесплатно',
                'Стоимость в перерасчёте на месяц - 1114 рублей',
                'Экономия - 276 руб.',
                'Скорость доступа - до 100 Мбит/сек',
              ],
            ),
            TariffOffer(
              name: 'Полгода+Месяц 100М',
              price: 7200,
              days: 212,
              perMonth: 1029,
              details: [
                'В подарок - один месяц бесплатно',
                'Стоимость в перерасчёте на месяц - 1029 рублей',
                'Экономия - 1200 руб.',
                'Скорость доступа - до 100 Мбит/сек',
              ],
            ),
            TariffOffer(
              name: 'Год+Квартал 100М',
              price: 14400,
              days: 456,
              perMonth: 960,
              details: [
                'В подарок - один квартал бесплатно',
                'Стоимость в перерасчёте на месяц - 960 рублей',
                'Экономия - 3600 руб.',
                'Скорость доступа - до 100 Мбит/сек',
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

  // биллинг отдаёт в услугах только действующий тариф, цена - из суммы к оплате
  static List<ServiceItem> get demoServices => [
        ServiceItem(name: 'Месяц 100М', cost: '${BalanceStore.format(1200)} / мес', status: ''),
      ];

  // операции как в отчёте aaaotch: «оплата» и «активация услуги» с тарифом в комментарии
  static List<PaymentItem> get demoPayments => [
        PaymentItem(date: '16-11-2026 00:03', amount: -1200.0, operation: 'активация услуги', comment: 'Месяц 100М'),
        PaymentItem(date: '15-11-2026 19:42', amount: 1200.0, operation: 'оплата', comment: ''),
        PaymentItem(date: '17-10-2026 00:02', amount: -1200.0, operation: 'активация услуги', comment: 'Месяц 100М'),
        PaymentItem(date: '14-10-2026 12:10', amount: 1500.0, operation: 'оплата', comment: ''),
        PaymentItem(date: '17-09-2026 00:04', amount: -1200.0, operation: 'активация услуги', comment: 'Месяц 100М'),
        PaymentItem(date: '16-09-2026 21:35', amount: 1200.0, operation: 'оплата', comment: ''),
      ];
}
