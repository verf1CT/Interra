import '../services/balance_store.dart';
import '../services/cabinet_parser.dart';

/// мелкие расчёты поверх данных биллинга для главного экрана и истории.
/// всё считается только из того, что реально отдал UTM5, без догадок

const _monthsNominative = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];

const _monthsGenitive = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

final _moneyRe = RegExp(r'(\d[\d\s ]*(?:[.,]\d{1,2})?)\s*(?:₽|руб)');

/// сумма ежемесячной абонплаты по подключённым услугам.
/// берём только цены с пометкой «мес», «Включено» и разовые платежи пропускаем.
/// null - если ни одной месячной цены не нашлось
double? monthlyFee(List<ServiceItem> services) {
  double sum = 0;
  var found = false;
  for (final s in services) {
    final cost = s.cost.toLowerCase();
    if (!cost.contains('мес')) continue;
    final m = _moneyRe.firstMatch(cost);
    if (m == null) continue;
    final raw = m.group(1)!.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.');
    final v = double.tryParse(raw);
    if (v == null || v <= 0) continue;
    sum += v;
    found = true;
  }
  return found ? sum : null;
}

/// на сколько полных месяцев хватит баланса при данной абонплате
int? monthsCovered(double balance, double? fee) {
  if (fee == null || fee <= 0) return null;
  if (balance <= 0) return 0;
  return (balance / fee).floor();
}

/// дата из таблиц биллинга: «04.11.2026» или «04.11.2026 14:22»
DateTime? parseBillingDate(String s) {
  final m = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2}))?')
      .firstMatch(s);
  if (m == null) return null;
  final d = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final y = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(
    y,
    mo,
    d,
    int.tryParse(m.group(4) ?? '') ?? 0,
    int.tryParse(m.group(5) ?? '') ?? 0,
  );
}

/// «Ноябрь 2026»
String monthTitle(DateTime d) => '${_monthsNominative[d.month - 1]} ${d.year}';

/// «4 ноября», год добавляем только если он не текущий
String shortDate(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final base = '${d.day} ${_monthsGenitive[d.month - 1]}';
  return d.year == n.year ? base : '$base ${d.year}';
}

/// время «14:22», пустая строка для полуночи (у списаний биллинг ставит 00:00)
String shortTime(DateTime d) {
  if (d.hour == 0 && d.minute == 0) return '';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// «+750 ₽» / «−750 ₽» в едином формате с балансом
String signedMoney(double amount) {
  if (amount > 0) return '+${BalanceStore.format(amount)}';
  return BalanceStore.format(amount);
}

/// последнее пополнение (первая положительная операция - биллинг отдаёт
/// историю от новых к старым, но на всякий случай сортируем по дате)
PaymentItem? lastTopUp(List<PaymentItem> items) {
  PaymentItem? best;
  DateTime? bestDate;
  for (final p in items) {
    if (p.amount <= 0) continue;
    final d = parseBillingDate(p.date);
    if (best == null || (d != null && (bestDate == null || d.isAfter(bestDate)))) {
      best = p;
      bestDate = d;
    }
  }
  return best;
}

/// итоги по месяцу: пополнения и списания отдельно
class MonthTotals {
  final double income;
  final double expense;
  const MonthTotals(this.income, this.expense);
}

MonthTotals totalsForMonth(List<PaymentItem> items, int year, int month) {
  double inc = 0, exp = 0;
  for (final p in items) {
    final d = parseBillingDate(p.date);
    if (d == null || d.year != year || d.month != month) continue;
    if (p.amount > 0) {
      inc += p.amount;
    } else {
      exp += p.amount;
    }
  }
  return MonthTotals(inc, exp);
}

/// имя для приветствия: из «Иванов Иван Иванович» берём «Иван».
/// для служебных имён и одного слова возвращаем null
String? firstName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  // инициалы («И.И.») - не имя, обращаться так нельзя
  if (parts[1].contains('.')) return null;
  final name = parts[1].replaceAll(RegExp(r'[^А-Яа-яЁёA-Za-z-]'), '');
  if (name.length < 2) return null;
  return name[0].toUpperCase() + name.substring(1).toLowerCase();
}

/// приветствие по времени суток
String greeting(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return 'Доброе утро';
  if (h >= 12 && h < 18) return 'Добрый день';
  if (h >= 18 && h < 23) return 'Добрый вечер';
  return 'Доброй ночи';
}
