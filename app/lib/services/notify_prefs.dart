import 'package:shared_preferences/shared_preferences.dart';

/// Категория push-уведомлений: ключ хранения = сегмент на бэкенде.
class NotifyCategory {
  final String key; // сегмент, по которому оператор таргетирует рассылку
  final String title;
  final String subtitle;
  const NotifyCategory(this.key, this.title, this.subtitle);
}

/// Пользовательские категории уведомлений.
///
/// Включённые категории уходят на бэкенд как `segments` при регистрации
/// устройства — оператор шлёт `target: {type:'segment', value:'news'}` и
/// рассылка приходит только подписанным. `prefs` дублирует полную карту
/// выборов (для аналитики/отладки на сервере).
class NotifyPrefs {
  static const categories = [
    NotifyCategory('outage', 'Аварии и работы', 'Сбои и плановые работы сети'),
    NotifyCategory('balance', 'Баланс и оплата', 'Низкий баланс, списания'),
    NotifyCategory('news', 'Новости и акции', 'Тарифы, скидки, новости'),
  ];

  static String _prefKey(String key) => 'notify_$key';

  /// Все категории включены по умолчанию.
  static Future<bool> isEnabled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey(key)) ?? true;
  }

  static Future<void> setEnabled(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(key), value);
  }

  /// Список включённых категорий — сегменты для registerDevice.
  static Future<List<String>> enabledSegments() async {
    final result = <String>[];
    for (final c in categories) {
      if (await isEnabled(c.key)) result.add(c.key);
    }
    return result;
  }

  /// Полная карта выборов — поле prefs для registerDevice.
  static Future<Map<String, bool>> prefsMap() async {
    final result = <String, bool>{};
    for (final c in categories) {
      result[c.key] = await isEnabled(c.key);
    }
    return result;
  }
}
