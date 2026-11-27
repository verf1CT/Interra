import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/services/cabinet_parser.dart';

// куски настоящих страниц aaatarif, имена и адреса заменены
const _groups = """
<body><table class="b-content"><tbody><tr><td id="aaatds"> На этой странице вы можете заказать себе следующий тариф.<br><br>
Клиент: <span><b>Иванов Иван Иванович</b></span> (ЛЕНИНА 1-1 / 100000test)<br>
<font>Действующий тариф: <span><b>Месяц 100М</b></span></font><br>
<hr><font><b>Группы тарифов:</b></font><hr><a class="btn7 --grey --full" href="?login=x&amp;oper=tarif&amp;gro=18"><font size="+0">100 мегабит</font></a><font size="-0"></font><hr><a class="btn7 --grey --full" href="?login=x&amp;oper=tarif&amp;gro=0"><font size="+0">Нет тарифа</font></a><font size="-0">Нет тарифа - это состояние, при котором отсутствует доступ в Интернет и не снимается абонентская плата.</font><hr>
</td></tr></tbody></table></body>""";

const _group18 = """
<body><table class="b-content"><tbody><tr><td id="aaatds">
<font>Действующий тариф: <span><b>Месяц 100М</b></span></font><br>
<hr><a href="?login=x&amp;oper=tarif"><font size="+0">Вернуться к списку групп тарифов</font></a><hr><br><table class="tlt"><tbody>
<tr><td><a class="btn7 --grey --full" href="?login=x&amp;oper=tarif&amp;gro=18&amp;pack=3041" onmouseover="tooltip.show(&quot;Описание тарифа:<br>Стоимость - 1200 рублей<br>Скорость доступа - до 100 Мбит/сек&quot;);" onmouseout="tooltip.hide();"><font size="+0">Месяц 100М <br>(1200руб на 30 сут.)</font></a></td></tr>
<tr><td><a class="btn7 --grey --full" href="?login=x&amp;oper=tarif&amp;gro=18&amp;pack=3044" onmouseover="tooltip.show(&quot;Описание тарифа:<br>Стоимость - 14400 рублей<br>В подарок - один квартал бесплатно<br>Стоимость в перерасчёте на месяц - 960 рублей<br>Экономия - 3600 руб.<br>Скорость доступа - до 100 Мбит/сек&quot;);" onmouseout="tooltip.hide();"><font size="+0">Год+Квартал 100М <br>(14400руб на 456 сут.)</font></a></td></tr>
</tbody></table><br></td></tr></tbody></table></body>""";

const _group0 = """
<body><table class="tlt"><tbody><tr><td><a class="btn7 --grey --full" href="?login=x&amp;oper=tarif&amp;gro=0&amp;pack=0" onmouseover="tooltip.show(&quot;Нет тарифа&quot;);" onmouseout="tooltip.hide();"><font size="+0">Нет тарифа</font></a></td></tr></tbody></table></body>""";

const _order = """
<body><table class="b-content"><tbody><tr><td id="aaatds">
<font>Действующий тариф: <span><b>Месяц 100М</b></span></font><br>
<hr><a href="?login=x&amp;oper=tarif"><font size="+0">Вернуться к списку групп тарифов</font></a><hr><br><br><font size="+0">После окончания действующего тарифа <b> 16-12-2026 14:29</b>.<br> Вы собираетесь переключиться на тариф<br><b>Месяц 100М (1200руб на 30 сут.)</b><br><br><div>Описание тарифа:<br>Стоимость - 1200 рублей</div><br></font>
<form action="" method="POST">
<input type="hidden" name="login" value="x"><input type="hidden" name="oper" value="tarif">
<input type="hidden" name="gro" value="18"><input type="hidden" name="pack" value="3041">
<input type="submit" class="btn" name="set" value="ДА">
<input type="submit" class="btn" name="set" value="НЕТ"><br><br>
</form></td></tr></tbody></table></body>""";

void main() {
  test('группы тарифов: id, название и пояснение биллинга', () {
    final g = parseTariffGroups(_groups);
    expect(g.map((e) => e.id), ['18', '0']);
    expect(g[0].name, '100 мегабит');
    expect(g[0].note, isNull);
    expect(g[1].isNoTariff, true);
    expect(g[1].note, startsWith('Нет тарифа - это состояние'));
    expect(CabinetParser.parseCurrentTariff(_groups), 'Месяц 100М');
  });

  test('тарифы группы: цена, срок, описание без строки цены', () {
    final o = parseTariffOffers(_group18);
    expect(o.length, 2);
    expect(o[0].name, 'Месяц 100М');
    expect(o[0].price, 1200);
    expect(o[0].days, 30);
    expect(o[0].details, ['Скорость доступа - до 100 Мбит/сек']);
    expect(o[0].perMonth, isNull);
    expect(o[0].pack, '3041');
    expect(o[1].name, 'Год+Квартал 100М');
    expect(o[1].price, 14400);
    expect(o[1].days, 456);
    expect(o[1].perMonth, 960);
    expect(o[1].details.first, 'В подарок - один квартал бесплатно');
    expect(o[1].href, '?login=x&oper=tarif&gro=18&pack=3044');
  });

  test('группа «Нет тарифа»: без цены и описания', () {
    final o = parseTariffOffers(_group0);
    expect(o.single.name, 'Нет тарифа');
    expect(o.single.price, isNull);
    expect(o.single.details, isEmpty);
    expect(o.single.pack, '0');
  });

  test('страница подтверждения: дата смены и скрытые поля формы', () {
    final p = parseTariffOrderPage(_order)!;
    expect(p.switchAt, DateTime(2026, 12, 16, 14, 29));
    expect(p.form, {'login': 'x', 'oper': 'tarif', 'gro': '18', 'pack': '3041'});
    expect(p.canOrder, true);
    expect(parseTariffOrderPage(_group18), isNull);
  });

  test('заказ принят, только когда биллинг написал об успехе', () {
    const reply = '<body><td id="aaatds"><font>Действующий тариф: <span><b>Месяц 100М</b></span></font><br>'
        '<br>операция выбора тарифа прошла успешно,<br>следить за выполнением операций можно на вкладке '
        '<a href="aaainfo?login=x&amp;oper=info"><font size="+0">Основная информация</font></a></td></body>';
    expect(tariffOrderAccepted(reply), true);
    expect(tariffOrderAccepted(_order), false);
    expect(tariffOrderAccepted(_groups), false);
    expect(tariffOrderAccepted(null), false);
  });

  test('страница договора: заказанный следующий тариф без «подробнее»', () {
    const info = '<body><table class="b-account"><tbody>'
        '<tr><td><b>Электронный счёт</b></td><td>100000</td></tr>'
        '<tr><td><b>Баланс</b></td><td>8800.00 руб.</td></tr>'
        '<tr><td><b>Действующий тариф</b></td><td>Месяц 100М</td></tr>'
        '<tr><td><b>Следующий тариф</b></td><td>Квартал+Неделя 100М &nbsp; <a href="#">подробнее</a></td></tr>'
        '<tr><td><b>Следующий платёж до</b></td><td>16-12-2026 14:29</td></tr>'
        '<tr><td><b>Сумма к оплате</b></td><td>3600.00 руб.</td></tr>'
        '</tbody></table></body>';
    final d = CabinetParser.parseCabinetHtml(info);
    expect(d.tariff, 'Месяц 100М');
    expect(d.nextTariff, 'Квартал+Неделя 100М');
    expect(d.nextCharge, 3600);
  });
}
