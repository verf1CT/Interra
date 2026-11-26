import 'package:html/parser.dart' as parser;

/// пакет каналов со страницы Premium TV или IPTV кабинета
class TvPackage {
  final String name;
  final int? price; // рублей в месяц
  final bool extra; // дополнительный, заказывается к основному
  final String? note; // описание из биллинга, например «+128 каналов…»

  /// относительная ссылка на страницу пакета в кабинете (`?login=…&xid=…`)
  final String href;

  const TvPackage({
    required this.name,
    this.price,
    this.extra = false,
    this.note,
    required this.href,
  });
}

class TvInfo {
  /// вход в Смотрёшку (Premium TV)
  final String? login;
  final String? password;
  final List<TvPackage> premium;

  /// у IPTV базовый пакет бесплатный и подключён всем
  final bool iptvFreeBase;
  final List<TvPackage> iptv;

  const TvInfo({
    this.login,
    this.password,
    this.premium = const [],
    this.iptvFreeBase = false,
    this.iptv = const [],
  });

  bool get isEmpty => login == null && premium.isEmpty && iptv.isEmpty;
}

/// пакеты идут блоками между <hr>: кнопка-ссылка с xid, иногда описание,
/// затем «Цена <b>200</b> рублей за месяц». заголовок «Дополнительные пакеты»
/// стоит отдельным блоком - всё после него дополнительное
List<TvPackage> parseTvPackages(String html) {
  final body = parser.parse(html).querySelector('#aaatds')?.innerHtml ??
      parser.parse(html).body?.innerHtml ??
      '';
  final result = <TvPackage>[];
  var extra = false;
  for (final chunk in body.split(RegExp(r'<hr[^>]*>', caseSensitive: false))) {
    final frag = parser.parseFragment(chunk);
    final text = frag.text?.replaceAll(' ', ' ') ?? '';
    if (text.contains('Дополнительные пакеты')) extra = true;
    final a = frag.querySelector('a[href*="xid="]');
    if (a == null) continue;
    final name = a.text.trim();
    final href = a.attributes['href'] ?? '';
    if (name.isEmpty || RegExp(r'xid=0\b').hasMatch(href)) continue;
    final price = int.tryParse(RegExp(r'Цена\s*(\d+)').firstMatch(text)?.group(1) ?? '');
    // описание - текст между названием и ценой, если это не повтор названия
    var note = text.substring(text.indexOf(name) + name.length);
    final cut = note.indexOf('Цена');
    note = (cut >= 0 ? note.substring(0, cut) : note).trim();
    result.add(TvPackage(
      name: name,
      price: price,
      extra: extra,
      note: note.isEmpty || note == name ? null : note,
      href: href,
    ));
  }
  return result;
}

/// логин и пароль для Смотрёшки со страницы пакетов Premium TV
(String?, String?) parsePremiumCredentials(String html) {
  final text = (parser.parse(html).body?.text ?? '').replaceAll(' ', ' ');
  String? find(String re) =>
      RegExp(re, caseSensitive: false).firstMatch(text)?.group(1);
  return (find(r'логин[^:\n]*:\s*(\S+)'), find(r'пароль:\s*(\S+)'));
}

/// страница одного пакета: цена, описание, каналы и форма «включить этот пакет»
class TvPackageDetails {
  final String name;
  final double? price;
  final String? period; // «30 суток», «месяц»
  final String? note;
  final List<String> channels;
  final int? channelCount;

  /// текст биллинга рядом с кнопкой, например «Можно»
  final String status;

  /// кнопка «включить» есть - пакет можно подключить
  final bool canEnable;

  /// скрытые поля формы (op, ctm) - отправляем как есть
  final Map<String, String> form;

  const TvPackageDetails({
    required this.name,
    this.price,
    this.period,
    this.note,
    this.channels = const [],
    this.channelCount,
    this.status = '',
    this.canEnable = false,
    this.form = const {},
  });
}

TvPackageDetails? parseTvPackageDetails(String html) {
  final doc = parser.parse(html);
  final root = doc.querySelector('#aaatds') ?? doc.body;
  if (root == null) return null;
  final text = root.text.replaceAll(' ', ' ');
  final priceM = RegExp(r'цена\s*([\d.,]+)\s*рубл\S*\s+за\s+(\d+\s+\S+|месяц)', caseSensitive: false)
      .firstMatch(text);
  if (priceM == null) return null;
  final name = root
          .querySelectorAll('span')
          .map((e) => e.text.trim())
          .firstWhere((t) => t.isNotEmpty, orElse: () => '');
  if (name.isEmpty) return null;

  final form = root.querySelector('form');
  final button = form?.querySelector('input[type="submit"]')?.attributes['value'] ?? '';
  final fields = <String, String>{
    for (final el in form?.querySelectorAll('input[type="hidden"]') ?? const [])
      if ((el.attributes['name'] ?? '').isNotEmpty) el.attributes['name']!: el.attributes['value'] ?? '',
  };

  // описание у IPTV стоит между ценой и формой
  String? note;
  final after = text.substring(priceM.end);
  final formText = form?.text ?? '';
  final cut = formText.isEmpty ? -1 : after.indexOf(formText.trim().split(RegExp(r'\s+')).first);
  final candidate = (cut > 0 ? after.substring(0, cut) : '').trim();
  if (candidate.isNotEmpty && candidate.length < 200) note = candidate;

  final pre = root.querySelector('pre.iptvchan')?.text ?? '';
  final lines = pre.split(RegExp(r'[\r\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  return TvPackageDetails(
    name: name,
    price: double.tryParse(priceM.group(1)!.replaceAll(',', '.')),
    period: priceM.group(2)!.trim(),
    note: note,
    // каналы в <pre> идут по строке; если строка одна, названия не разделить
    channels: lines.length > 2 ? lines : const [],
    channelCount: int.tryParse(RegExp(r'всего:\s*(\d+)').firstMatch(text)?.group(1) ?? ''),
    status: formText.replaceAll(button, '').trim(),
    canEnable: button.toLowerCase().contains('включить'),
    form: fields,
  );
}

bool parseIptvFreeBase(String html) =>
    (parser.parse(html).body?.text ?? '').contains('базовый бесплатный пакет');
