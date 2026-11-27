import 'package:html/parser.dart' as parser;

import '../utils/billing_math.dart';

/// группа тарифов со страницы aaatarif?oper=tarif, например «100 мегабит».
/// группа 0 - «Нет тарифа»: интернет выключен, абонплата не снимается
class TariffGroup {
  final String id;
  final String name;

  /// пояснение биллинга рядом с кнопкой группы
  final String? note;

  const TariffGroup({required this.id, required this.name, this.note});

  bool get isNoTariff => id == '0';
}

/// тариф внутри группы: «Месяц 100М (1200руб на 30 сут.)» и подсказка с описанием
class TariffOffer {
  final String name;
  final int? price;
  final int? days;

  /// строки описания из подсказки биллинга: подарок, экономия, скорость
  final List<String> details;

  /// «Стоимость в перерасчёте на месяц - 960 рублей»
  final int? perMonth;

  /// ссылка вида `?login=…&oper=tarif&gro=18&pack=3041`
  final String href;

  const TariffOffer({
    required this.name,
    this.price,
    this.days,
    this.details = const [],
    this.perMonth,
    this.href = '',
  });

  String? get pack => RegExp(r'pack=(\d+)').firstMatch(href)?.group(1);
}

class TariffCatalog {
  /// действующий тариф, null - «Нет тарифа»
  final String? current;
  final List<TariffGroup> groups;

  /// тарифы по id группы
  final Map<String, List<TariffOffer>> offers;

  const TariffCatalog({this.current, this.groups = const [], this.offers = const {}});
}

/// страница подтверждения тарифа (`…&gro=18&pack=3041`): «После окончания
/// действующего тарифа <дата>. Вы собираетесь переключиться на тариф…» и
/// форма с кнопками ДА/НЕТ. сам заход на страницу ничего не заказывает
class TariffOrderPage {
  /// когда закончится действующий тариф и включится выбранный
  final DateTime? switchAt;

  /// скрытые поля формы: login, oper, gro, pack
  final Map<String, String> form;

  const TariffOrderPage({this.switchAt, this.form = const {}});

  bool get canOrder => form.containsKey('pack');
}

TariffOrderPage? parseTariffOrderPage(String html) {
  final doc = parser.parse(html);
  final form = doc.querySelectorAll('form').where((f) => f.querySelector('input[name="pack"]') != null).firstOrNull;
  if (form == null) return null;
  final fields = <String, String>{
    for (final i in form.querySelectorAll('input[type="hidden"]'))
      if ((i.attributes['name'] ?? '').isNotEmpty) i.attributes['name']!: i.attributes['value'] ?? '',
  };
  final text = doc.body?.text ?? '';
  final m = RegExp(r'окончания\s+действующего\s+тарифа\s*([\d\-.: ]+)').firstMatch(text);
  return TariffOrderPage(switchAt: m == null ? null : parseBillingDate(m.group(1)!), form: fields);
}

/// биллинг принял выбор: «операция выбора тарифа прошла успешно, следить за
/// выполнением операций можно на вкладке Основная информация»
bool tariffOrderAccepted(String? html) {
  if (html == null) return false;
  return RegExp(r'выбора\s+тарифа\s+прошла\s+успешно', caseSensitive: false)
      .hasMatch(parser.parse(html).body?.text ?? '');
}

List<TariffGroup> parseTariffGroups(String html) {
  final doc = parser.parse(html);
  final out = <TariffGroup>[];
  final seen = <String>{};
  for (final a in doc.querySelectorAll('a[href]')) {
    final href = a.attributes['href'] ?? '';
    if (!href.contains('oper=tarif') || href.contains('pack=')) continue;
    final id = RegExp(r'gro=(\d+)').firstMatch(href)?.group(1);
    final name = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (id == null || name.isEmpty || !seen.add(id)) continue;
    final note = a.nextElementSibling?.localName == 'font'
        ? a.nextElementSibling!.text.replaceAll(RegExp(r'\s+'), ' ').trim()
        : '';
    out.add(TariffGroup(id: id, name: name, note: note.isEmpty ? null : note));
  }
  return out;
}

List<TariffOffer> parseTariffOffers(String html) {
  final doc = parser.parse(html);
  final out = <TariffOffer>[];
  for (final a in doc.querySelectorAll('a[href]')) {
    final href = a.attributes['href'] ?? '';
    if (!href.contains('pack=')) continue;
    final text = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final m = RegExp(r'^(.*?)\s*\((\d+)\s*руб\S*\s+на\s+(\d+)\s*сут\S*\)$').firstMatch(text);
    final name = m?.group(1)?.trim() ?? text;
    if (name.isEmpty) continue;

    // tooltip.show("Описание тарифа:<br>Стоимость - 1200 рублей<br>...")
    final tip = RegExp(r'show\("(.*)"\)', dotAll: true)
            .firstMatch(a.attributes['onmouseover'] ?? '')
            ?.group(1) ??
        '';
    final lines = tip
        .split(RegExp(r'<br\s*/?>', caseSensitive: false))
        .map((e) => e.replaceAll(RegExp(r'<[^>]*>'), '').trim())
        .where((e) =>
            e.isNotEmpty &&
            !e.endsWith(':') &&
            e != name &&
            // цену и так показываем крупно
            !RegExp(r'^Стоимость\s*-\s*\d+\s*руб', caseSensitive: false).hasMatch(e))
        .toList();
    final perMonth = RegExp(r'на\s+месяц\s*-\s*(\d+)', caseSensitive: false).firstMatch(tip)?.group(1);

    out.add(TariffOffer(
      name: name,
      price: int.tryParse(m?.group(2) ?? ''),
      days: int.tryParse(m?.group(3) ?? ''),
      details: lines,
      perMonth: int.tryParse(perMonth ?? ''),
      href: href,
    ));
  }
  return out;
}
