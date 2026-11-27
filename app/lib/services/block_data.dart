import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

/// кнопка формы со страницы блокировки aaaprcn: «заблокировать учётную
/// запись», «получить код родительского контроля» и те, что биллинг покажет
/// в других состояниях (снять блок, ввести код). нажатие отправляет форму как браузер
class BlockAction {
  final String label;

  /// скрытые поля формы и имя/значение самой кнопки
  final Map<String, String> fields;

  /// поле для кода из sms, если форма его просит
  final String? codeField;

  /// текст формы вокруг кнопки: «для активации услуги нужно … в смс»
  final String? hint;

  const BlockAction({required this.label, this.fields = const {}, this.codeField, this.hint});

  bool get needsCode => codeField != null;
}

/// кусок страницы под своим заголовком: «Долгосрочная блокировка» и т.п.
class BlockSection {
  final String title;
  final List<String> lines;

  /// строка, которую биллинг выделил красным
  final String? warning;
  final List<BlockAction> actions;

  const BlockSection({required this.title, this.lines = const [], this.warning, this.actions = const []});
}

List<BlockSection> parseBlockPage(String html) {
  final doc = parser.parse(html);
  final root = doc.querySelector('#aaatds') ?? doc.body;
  if (root == null) return const [];

  final sections = <BlockSection>[];
  var title = '';
  var lines = <String>[];
  String? warning;
  var actions = <BlockAction>[];
  final buf = StringBuffer();

  void flushLine() {
    final t = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isNotEmpty) lines.add(t);
    buf.clear();
  }

  void close() {
    flushLine();
    if (title.isNotEmpty || lines.isNotEmpty || actions.isNotEmpty) {
      sections.add(BlockSection(title: title, lines: lines, warning: warning, actions: actions));
    }
    title = '';
    lines = <String>[];
    warning = null;
    actions = <BlockAction>[];
  }

  void walk(dom.Node n) {
    if (n is dom.Text) {
      buf.write(n.text);
      return;
    }
    if (n is! dom.Element) return;
    final tag = n.localName;
    if (tag == 'script' || tag == 'style') return;
    if ((tag == 'b' && n.classes.contains('font-l')) || tag == 'h1' || tag == 'h2' || tag == 'h3') {
      close();
      title = n.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      return;
    }
    if (tag == 'b' && n.classes.contains('p')) {
      flushLine();
      warning = n.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      return;
    }
    if (tag == 'form') {
      flushLine();
      actions.addAll(_formActions(n));
      return;
    }
    if (tag == 'br' || tag == 'hr') {
      flushLine();
      return;
    }
    final block = tag == 'p' || tag == 'div' || tag == 'table' || tag == 'tr';
    if (block) flushLine();
    for (final c in n.nodes) {
      walk(c);
    }
    if (block) flushLine();
  }

  for (final c in root.nodes) {
    walk(c);
  }
  close();
  return sections;
}

List<BlockAction> _formActions(dom.Element form) {
  final hidden = <String, String>{
    for (final i in form.querySelectorAll('input[type="hidden"]'))
      if ((i.attributes['name'] ?? '').isNotEmpty) i.attributes['name']!: i.attributes['value'] ?? '',
  };
  // поле для кода: любое видимое текстовое поле
  final code = form
      .querySelectorAll('input')
      .where((i) {
        final t = (i.attributes['type'] ?? 'text').toLowerCase();
        return (t == 'text' || t == 'tel' || t == 'number' || t == 'password') &&
            (i.attributes['name'] ?? '').isNotEmpty;
      })
      .map((i) => i.attributes['name']!)
      .firstOrNull;
  final buttons = [
    ...form.querySelectorAll('input[type="submit"]'),
    ...form.querySelectorAll('button'),
  ];
  // текст формы без кнопок: подсказка рядом с кнопкой
  final hint = form.nodes
      .map((n) => n is dom.Element && (n.localName == 'input' || n.localName == 'button') ? ' ' : n.text ?? '')
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return [
    for (final b in buttons)
      BlockAction(
        label: (b.attributes['value'] ?? b.text).replaceAll(RegExp(r'\s+'), ' ').trim(),
        fields: {
          ...hidden,
          if ((b.attributes['name'] ?? '').isNotEmpty) b.attributes['name']!: b.attributes['value'] ?? b.text.trim(),
        },
        codeField: code,
        hint: hint.isEmpty ? null : hint,
      ),
  ];
}

/// строки ответа, которых не было на странице до нажатия: то, что биллинг
/// сказал про результат («блокировка установлена», «код отправлен» и т.п.)
List<String> newBlockLines(List<BlockSection> before, List<BlockSection> after) {
  Iterable<String> all(BlockSection s) =>
      [if (s.title.isNotEmpty) s.title, ...s.lines, if (s.warning != null) s.warning!];
  final old = {for (final s in before) ...all(s)};
  return [
    for (final s in after)
      for (final l in all(s))
        if (!old.contains(l)) l,
  ];
}
