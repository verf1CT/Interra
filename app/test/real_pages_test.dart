import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/screens/payments_history_screen.dart';
import 'package:lk_interra/services/cabinet_parser.dart';
import 'package:lk_interra/services/charge_reminder.dart';
import 'package:lk_interra/services/site_pay.dart';
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

const _sms = """
<body><table class="b-content"><tbody><tr><td id="aaatds">
<hr><br>номер мобильного телефона:<br>
<form action="" method="POST" id="clkform">
<input type="hidden" name="login" value="X.216997.3599685159"><input type="hidden" name="oper" value="smssvc"><input type="hidden" name="hrenul" id="hrenul" value="0">
<input type="text" name="phone" id="phone" size="20" maxlength="20" value="79990000000" autocomplete="off" required=""><br>
<input type="checkbox" name="sendme" checked=""> присылать уведомления<br><br> привязано приложений: <b class="t">10</b><br><input type="checkbox" name="delapp"> отвязать все приложения<br><br>
<input class="btn" type="submit" name="set" id="searclk" value="внести изменения"></form>
</td></tr></tbody></table></body>""";

const _premium = """
<body><table class="b-content"><tbody><tr><td id="aaatds">
<div class="font-l mb-24"><b>Premium TV</b></div>
<a href="?login=x&amp;oper=xtvpsm">Описание услуги</a><br><p>Ваш персональный логин для просмотра Premium TV: <b>123456interra</b><br> Ваш пароль: <b>000000</b><br> Эти данные необходимо ввести всего один раз.<br></p><hr>Основные пакеты:<br><hr><a class="btn7 --grey --full" href="?login=x&amp;oper=xtvpsmm&amp;xid=10" title="нажмите чтобы узнать подробности">Базовый</a>Цена <b>200</b> рублей за месяц<br><hr><a class="btn7 --grey --full" href="?login=x&amp;oper=xtvpsmm&amp;xid=12" title="нажмите чтобы узнать подробности">Максимальный</a>Цена <b>800</b> рублей за месяц<br><br><hr><font size="+0">Дополнительные пакеты:</font><br><hr><a class="btn7 --grey --full" href="?login=x&amp;oper=xtvpsmm&amp;xid=22" title="нажмите чтобы узнать подробности"><font size="+0">МАТЧ! ПРЕМЬЕР (Наш Футбол)</font></a>Цена <b>299</b> рублей за месяц<br>
</td></tr></tbody></table></body>""";

const _iptv = """
<body><table class="b-content"><tbody><tr><td id="aaatds">
<div class="font-l mb-24"><b>IPTV</b></div><a href="?login=x&amp;oper=iptv">Описание услуги</a><hr width="350" align="left">По умолчанию у всех абонентов подключен <a href="?login=x&amp;oper=iptvm&amp;xid=0" title="посмотреть список каналов">базовый бесплатный пакет </a>.<br><br><hr><a class="btn7 --grey --full" href="?login=x&amp;oper=iptvm&amp;xid=1" title="+128 каналов к Базовому пакету (итого 150)">Полный</a>+128 каналов к Базовому пакету (итого 150)<br>Цена <b>200</b> рублей за месяц<br><hr><a class="btn7 --grey --full" href="?login=x&amp;oper=iptvm&amp;xid=8" title="Матч! Премьер">Матч! Премьер</a>Матч! Премьер<br>Цена <b>299</b> рублей за месяц<br>
</td></tr></tbody></table></body>""";

const _premiumPackage = """
<body><table class="b-content"><tbody><tr><td id="aaatds">
<div class="font-l mb-24"><b>Premium TV</b></div>
<a href="?login=x&amp;oper=xtvpsm">Описание услуги</a><br><p>Ваш персональный логин для просмотра Premium TV: <b>123456interra</b><br> Ваш пароль: <b>000000</b><br></p><hr><a href="?login=x&amp;oper=xtvpsmm"><font size="-0">Вернуться к списку пакетов</font></a><font size="-0"><br><br><font size="+0">Пакет <span>Базовый</span></font><br>Цена <font color="red"> 200.00</font> рублей за 30 суток<font><br><br>
<form action="" method="post">Можно <input type="hidden" name="op" value="1"><input type="hidden" name="ctm" value="1795724595"><input class="btn" type="submit" value="включить этот пакет"></form>
<pre class="iptvchan" id="iptvchan"></pre>
</font></font></td></tr></tbody></table></body>""";

const _iptvPackage = """
<body><table class="b-content"><tbody><tr><td id="aaatds">
<div class="font-l mb-24"><b>IPTV</b></div><a href="?login=x&amp;oper=iptv">Описание услуги</a><hr width="350" align="left">По умолчанию у всех абонентов подключен <a href="?login=x&amp;oper=iptvm&amp;xid=0">базовый бесплатный пакет </a>.<br><br><hr><a href="?login=x&amp;oper=iptvm">Вернуться к списку пакетов</a><br><br><font size="+0">пакет <span>Полный</span></font><br>цена <font color="red"> 200.00</font> рублей за месяц<br><br>+128 каналов к Базовому пакету (итого 150)<br><br><form action="" method="post">Можно <input type="hidden" name="op" value="1"><input class="btn" type="submit" value="включить этот пакет"></form><br><hr>Список каналов:<hr><pre class="iptvchan">Солнце
Ретро ТВ
Драйв
</pre><hr>всего: 133 </td></tr></tbody></table></body>""";

void main() {
  test('ошибки API оплаты сайта собираются в строку', () {
    expect(
      SitePay.parseError({
        'epay': ['Лицевой счёт указан некорректно'],
        'amount': ['Сумма не может быть отрицательной или равной нулю.'],
      }),
      'Лицевой счёт указан некорректно. Сумма не может быть отрицательной или равной нулю.',
    );
    expect(SitePay.parseError('x'), isNull);
    expect(SitePay.fallbackUrl('276997'), 'https://interra.ru/sberbank/?epay=276997');
  });

  test('ссылка банка берётся при любом 2xx, а не уходит в ошибку', () {
    const url = 'https://yoomoney.ru/checkout/payments/v2/contract?orderId=x';
    expect(SitePay.parseResponse(201, {'form_url': url}).url, url);
    expect(SitePay.parseResponse(201, {'form_url': url}).error, isNull);
    expect(SitePay.parseResponse(200, {'form_url': url}).url, url);
    expect(SitePay.parseResponse(200, {}).url, isNull);
    expect(SitePay.parseResponse(200, {}).error, isNull);
    expect(SitePay.parseResponse(400, {'amount': ['Сумма неверна']}).error, 'Сумма неверна');
  });

  test('ответ sms-формы: обычная страница - не запрос кода', () {
    expect(CabinetParser.smsCodeRequested(_sms), isFalse);
    expect(CabinetParser.smsCodeRequested('<body>Введите код из SMS</body>'), isTrue);
    expect(CabinetParser.smsCodeRequested(null), isFalse);
  });

  test('страница пакета Premium TV: цена за период и форма включения', () {
    final d = parseTvPackageDetails(_premiumPackage)!;
    expect(d.name, 'Базовый');
    expect(d.price, 200.0);
    expect(d.period, '30 суток');
    expect(d.canEnable, isTrue);
    expect(d.status, 'Можно');
    expect(d.form, {'op': '1', 'ctm': '1795724595'});
    expect(d.note, isNull);
    expect(d.channels, isEmpty);
  });

  test('страница пакета IPTV: описание, каналы по строкам и их число', () {
    final d = parseTvPackageDetails(_iptvPackage)!;
    expect(d.name, 'Полный');
    expect(d.period, 'месяц');
    expect(d.note, '+128 каналов к Базовому пакету (итого 150)');
    expect(d.channels, ['Солнце', 'Ретро ТВ', 'Драйв']);
    expect(d.channelCount, 133);
    final on = parseTvPackageDetails(_iptvPackage.replaceFirst('включить этот пакет', 'выключить этот пакет'))!;
    expect(on.canEnable, isFalse);
  });

  test('Premium TV: вход в Смотрёшку и пакеты с ценами', () {
    final (login, password) = parsePremiumCredentials(_premium);
    expect(login, '123456interra');
    expect(password, '000000');
    final list = parseTvPackages(_premium);
    expect(list.map((e) => e.name), ['Базовый', 'Максимальный', 'МАТЧ! ПРЕМЬЕР (Наш Футбол)']);
    expect(list.map((e) => e.price), [200, 800, 299]);
    expect(list.map((e) => e.extra), [false, false, true]);
    expect(list.first.href, contains('xid=10'));
  });

  test('IPTV: бесплатный базовый и платные пакеты с описанием', () {
    expect(parseIptvFreeBase(_iptv), isTrue);
    final list = parseTvPackages(_iptv);
    expect(list.map((e) => e.name), ['Полный', 'Матч! Премьер']);
    expect(list[0].note, '+128 каналов к Базовому пакету (итого 150)');
    expect(list[0].price, 200);
    expect(list[1].note, isNull);
  });

  test('aaasmssvc: номер, галочка, привязанные приложения и поля формы', () {
    final s = CabinetParser.parseSmsSettings(_sms)!;
    expect(s.phone, '79990000000');
    expect(s.enabled, isTrue);
    expect(s.linkedApps, 10);
    expect(s.fields['hrenul'], '0');
    expect(s.fields.containsKey('sendme'), isFalse);
    final off = CabinetParser.parseSmsSettings(_sms.replaceFirst('name="sendme" checked=""', 'name="sendme"'))!;
    expect(off.enabled, isFalse);
    expect(CabinetParser.parseSmsSettings(_tarif), isNull);
  });

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
