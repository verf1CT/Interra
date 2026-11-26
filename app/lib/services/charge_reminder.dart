import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../utils/billing_math.dart';
import 'balance_store.dart';
import 'cabinet_parser.dart';
import 'notify_prefs.dart';

/// напоминание за 3 дня до списания, если баланса не хватает. дату списания
/// знает только приложение (её отдаёт страница договора), поэтому это локальное
/// уведомление, а не рассылка с сервера. перепланируется при каждой загрузке
/// данных договора: пополнил - напоминание снимается
class ChargeReminder {
  static const _daysBefore = 3;

  /// у каждого договора своё уведомление
  @visibleForTesting
  static int idFor(String account) =>
      710000 + (int.tryParse(account.replaceAll(RegExp(r'\D'), '')) ?? account.hashCode).abs() % 100000;

  /// когда показать: за 3 дня до списания в полдень. null - не нужно
  @visibleForTesting
  static DateTime? fireAt(CabinetData d, DateTime now) {
    final next = d.nextPaymentDate;
    final charge = d.nextCharge;
    if (next == null || charge == null || charge <= 0 || d.balance >= charge) return null;
    final day = next.subtract(const Duration(days: _daysBefore));
    final at = DateTime(day.year, day.month, day.day, 12);
    return at.isAfter(now) ? at : null;
  }

  static Future<void> update(CabinetData d) async {
    if (d.account.isEmpty) return;
    final plugin = FlutterLocalNotificationsPlugin();
    final id = idFor(d.account);
    try {
      await plugin.cancel(id: id);
      if (!await NotifyPrefs.isEnabled('balance')) return;
      final at = fireAt(d, DateTime.now());
      if (at == null) return;
      final lack = BalanceStore.format(d.nextCharge! - d.balance);
      await plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Через $_daysBefore дня списание ${BalanceStore.format(d.nextCharge!)}',
        body: 'Договор ${d.account}: не хватает $lack, пополните до ${shortDate(d.nextPaymentDate!)}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'interra_default',
            'Уведомления Интерра',
            channelDescription: 'Баланс, тариф, статусы заявок и сообщения провайдера',
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      // плагин не поднялся (нет разрешения или Firebase) - без напоминания
      debugPrint('ChargeReminder пропущен: $e');
    }
  }
}
