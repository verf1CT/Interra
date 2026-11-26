import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/screens/payments_history_screen.dart';
import 'package:lk_interra/services/cabinet_parser.dart';
import 'package:lk_interra/services/charge_reminder.dart';
import 'package:lk_interra/utils/billing_math.dart';

// куски настоящих страниц кабинета, имена и номера заменены
const _info = """
<body><div class="main"><div class="grid"><div class="wrapper --large"><table class="b-content"><tbody><tr><td id="aaatds">
<table class="b-informer"><tbody><tr><td align="left">Единый круглосуточный телефон: 8-800-77-000-10 (звонок бесплатный).<br>Центр обслуживания: ул. Трубников, 24</td></tr></tbody></table>
<table class="b-account"><thead><tr><th width="40%"></th><th width="60%"></th></tr></thead><tbody><tr><td align="right"><b>Учётная запись&nbsp;</b></td><td>&nbsp;<b>216997test</b></td></tr>
<tr><td align="right"><b>Электронный счёт&nbsp;</b></td><td>&nbsp;<font size="+0"><b><span>276997</span></b></font></td></tr>
<tr><td align="right"><b>ФИО&nbsp;</b></td><td>&nbsp;Мешкой Михаил Максимович</td></tr>
<tr><td align="right"><b>Адрес&nbsp;</b></td><td>&nbsp;ХВОЙНАЯ (МОЛОДЕЖНЫЙ) 5-</td></tr>
<tr><td align="right"><b><b>Баланс</b>&nbsp;</b></td><td>&nbsp;<font size="+0"><b><span>8800.00 руб.</span></b></font></td></tr>
<tr><td align="right"><b><b>Действующий тариф</b>&nbsp;</b></td><td>&nbsp;<b><span>Месяц 100М</span></b></td></tr>
<tr><td align="right"><b><b>Следующий платёж до</b>&nbsp;</b></td><td>&nbsp;<b>16-12-2026 14:29</b></td></tr>
<tr><td align="right"><b><b>Сумма к оплате</b>&nbsp;</b></td><td>&nbsp;<b>1200.00 руб.</b></td></tr>
</tbody></table>
</td></tr></tbody></table></div></div></div></body>""";

const _tarif = """
<body><div class="main"><div class="grid"><div class="wrapper --large"><table class="b-content"><tbody><tr><td id="aaatds"> На этой странице вы можете заказать себе следующий тариф.<br><br>
Клиент: <span><b>Чичиков Павел Иванович</b></span> (ТРУБНИКОВ 24-1 / 220879twjk)<br>
<font>Действующий тариф: <span><b>Месяц 100М</b></span></font><br>
<hr><font><b>Группы тарифов:</b></font><hr><a class="btn7" href="?login=x&amp;oper=tarif&amp;gro=18"><font size="+0">100 мегабит</font></a><hr>
</td></tr></tbody></table></div></div></div></body>""";

const _otch = """
<body><div class="main"><div class="grid"><div class="wrapper --large"><table class="b-content"><tbody><tr><td id="aaatds">
<table class="b-tab"><tbody><tr><td class="active"><b>операции</b></td><td><a href="?login=x&amp;oper=otch&amp;work=radius">сессии</a></td></tr></tbody></table>
<table class="b-operation"><tbody><tr class="thead"><td>выполнено</td><td>оператор</td><td>операция</td><td>пользователь</td><td>сумма</td><td>комментарий</td></tr>
<tr><td>26-11-2026 14:15</td><td>техподдержка</td><td>оплата</td><td><b>Чичиков Павел Иванович</b></td><td align="right">5000.00</td><td> for app test</td></tr>
<tr><td>26-11-2026 14:26</td><td>SYSTEM</td><td>активация услуги</td><td><b>Чичиков Павел Иванович</b></td><td align="right">-700.00</td><td>Месяц 100М</td></tr></tbody></table>
<form method="POST" action=""><input type="hidden" name="login" value="X.220879.3600679663">
<input type="hidden" name="oper" value="otch"><input type="hidden" name="work" value="cost">
<select name="god"><option value="2026" selected="">2026</option><option value="2025">2025</option></select>
<select name="mes"><option value="10">Октябрь</option><option value="11" selected="">Ноябрь</option></select>
<input class="btn" type="submit" value="Показать"></form>
</td></tr></tbody></table></div></div></div></body>""";

void main() {
  test('страница договора: тариф, баланс, ФИО и сумма ближайшего платежа', () {
    final d = CabinetParser.parseCabinetHtml(_info);
    expect(d.tariff, 'Месяц 100М');
    expect(d.balance, 8800.0);
    expect(d.fullName, 'Мешкой Михаил Максимович');
    expect(CabinetParser.parseNextCharge(_info), 1200.0);
    expect(d.nextPaymentDate, DateTime(2026, 12, 16, 14, 29));
    expect(d.nextCharge, 1200.0);
  });

  test('aaaotch: самый ранний год отчётов из формы', () {
    expect(CabinetParser.parseReportsFromYear(_otch), 2025);
    expect(CabinetParser.parseReportsFromYear(_tarif), isNull);
  });

  test('даты отчётов через дефис', () {
    expect(parseBillingDate('26-11-2026 14:15'), DateTime(2026, 11, 26, 14, 15));
    expect(parseBillingDate('04.11.2026'), DateTime(2026, 11, 4));
  });

  test('хватит до: ближайшее списание плюс оплаченные месяцы', () {
    final next = DateTime(2026, 12, 16);
    expect(paidUntil(8800, 1200, next), DateTime(2027, 7, 16));
    expect(paidUntil(800, 1200, next), next);
    expect(addMonths(DateTime(2027, 1, 31), 1), DateTime(2027, 2, 28));
  });

  test('напоминание: только когда не хватает и дата впереди', () {
    CabinetData data(double balance) => CabinetData(
          balance: balance,
          account: '276997',
          fullName: 'x',
          tariff: 'x',
          rawHtml: '',
          nextPaymentDate: DateTime(2026, 12, 16, 14, 29),
          nextCharge: 1200,
        );
    final now = DateTime(2026, 11, 26);
    expect(ChargeReminder.fireAt(data(800), now), DateTime(2026, 12, 13, 12));
    expect(ChargeReminder.fireAt(data(8800), now), isNull);
    expect(ChargeReminder.fireAt(data(800), DateTime(2026, 12, 14)), isNull);
  });

  test('названия операций', () {
    final items = CabinetParser.parsePaymentsHtml(_otch);
    expect(operationTitle(items[0]), 'Пополнение');
    expect(operationTitle(items[1]), 'Абонплата');
    expect(operationTitle(PaymentItem(date: '', amount: 0, operation: 'создание/изменение')),
        'Создание/изменение');
  });

  test('aaatarif: действующий тариф из строки текста', () {
    expect(CabinetParser.parseCurrentTariff(_tarif), 'Месяц 100М');
    expect(CabinetParser.parseCurrentTariff('<body>Действующий тариф: <b>Нет тарифа</b></body>'), isNull);
  });

  test('aaaotch: операции читаются из таблицы b-operation', () {
    final items = CabinetParser.parsePaymentsHtml(_otch);
    expect(items.length, 2);
    expect(items[0].date, '26-11-2026 14:15');
    expect(items[0].amount, 5000.0);
    expect(items[0].operation, 'оплата');
    expect(items[1].amount, -700.0);
    expect(items[1].comment, 'Месяц 100М');
  });
}
