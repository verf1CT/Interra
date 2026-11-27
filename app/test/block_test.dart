import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/services/cabinet_parser.dart';

// страница aaaprcn из дампа, токен заменён
const _page = """
<body><table class="b-content"><tbody><tr><td id="aaatds">
<b class="font-l">Долгосрочная блокировка</b><br>
<p>Данная блокировка предназначена для особых редких случаев, таких, например, как отпуск.<br> Ей можно пользоваться не чаще, чем раз в три месяца.<br> Время окончания тарифа в данном случае пересчитывается (к нему добавляются дни, проведённые в блоке).<br> Действующий тариф будет автоматически отключен, если продолжительность блокировки составит более двух месяцев.</p><br><form method="post" action="?login=x&amp;oper=prcn"><input type="hidden" name="sets" value="down"><input class="btn" type="submit" name="btn" value="заблокировать учётную запись"></form><br><br><h2><hr width="300" align="left">Краткосрочная блокировка</h2><hr width="300" align="left">Данной блокировкой можно пользоваться сколь угодно часто.<br> Её можно использовать, например, для родительского контроля.<br><b class="p">Время окончания тарифа при таком типе блокировки не пересчитывается.</b><br><form action="" method="post"><hr>для активации услуги нужно <input class="btn" type="submit" name="isms" value="получить код родительского контроля"> в смс</form>
</td></tr></tbody></table></body>""";

void main() {
  test('страница блокировки: два раздела, текст, кнопки с полями формы', () {
    final s = parseBlockPage(_page);
    expect(s.map((e) => e.title), ['Долгосрочная блокировка', 'Краткосрочная блокировка']);
    expect(s[0].lines.first, startsWith('Данная блокировка предназначена'));
    expect(s[0].lines.length, 4);
    expect(s[0].actions.single.label, 'заблокировать учётную запись');
    expect(s[0].actions.single.fields, {'sets': 'down', 'btn': 'заблокировать учётную запись'});
    expect(s[0].actions.single.needsCode, false);

    expect(s[1].warning, 'Время окончания тарифа при таком типе блокировки не пересчитывается.');
    expect(s[1].lines, contains('Её можно использовать, например, для родительского контроля.'));
    final sms = s[1].actions.single;
    expect(sms.label, 'получить код родительского контроля');
    expect(sms.fields, {'isms': 'получить код родительского контроля'});
    expect(sms.hint, 'для активации услуги нужно в смс');
  });

  test('форма с полем кода: поле находится, кнопка несёт свои поля', () {
    const reply = '<body><td id="aaatds"><b class="font-l">Краткосрочная блокировка</b><br>код отправлен<br>'
        '<form method="post"><input type="hidden" name="sets" value="pc"><input type="text" name="kod">'
        '<input type="submit" name="ok" value="применить"></form></td></body>';
    final a = parseBlockPage(reply).single.actions.single;
    expect(a.codeField, 'kod');
    expect(a.fields, {'sets': 'pc', 'ok': 'применить'});
    expect(newBlockLines(parseBlockPage(_page), parseBlockPage(reply)), ['код отправлен']);
  });
}
