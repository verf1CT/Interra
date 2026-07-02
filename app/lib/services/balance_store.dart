import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_store.dart';

/// нативный баланс абонента, извлечённый из страницы кабинета.
///
/// Источник - текст страницы «Основная информация» (`aaainfo`), которую и так
/// грузит WebView: отдельного API баланса у биллинга нет. значение кэшируем в
/// SharedPreferences, чтобы показывать его сразу при старте и в офлайне
class BalanceInfo {
  final double amount;
  final DateTime updatedAt;
  const BalanceInfo(this.amount, this.updatedAt);
}

class BalanceStore {
  static const _kAmount = 'balance_amount';
  static const _kUpdatedAt = 'balance_updated_at';

  // виджет домашнего экрана (iOS, WidgetKit): данные уходят в общий
  // UserDefaults app group, читает их ios/BalanceWidget/BalanceWidget.swift
  static const _appGroup = 'group.ru.interra.lkInterra';
  static const _widgetKind = 'BalanceWidget';

  /// текущее значение для UI. null - баланс ещё ни разу не извлекали
  static final ValueNotifier<BalanceInfo?> notifier = ValueNotifier(null);

  /// поднимает сохранённое значение (вызывать один раз при старте экрана)
  static Future<void> restore() async {
    if (notifier.value != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final amount = prefs.getDouble(_kAmount);
      final ts = prefs.getString(_kUpdatedAt);
      if (amount == null || ts == null) return;
      final at = DateTime.tryParse(ts);
      if (at != null) notifier.value = BalanceInfo(amount, at);
    } catch (e) {
      debugPrint('BalanceStore.restore пропущен: $e');
    }
  }

  /// обновляет баланс (из парсинга страницы) и сохраняет на диск.
  /// [account] - номер лицевого счёта (для настраиваемого виджета); необязателен
  static Future<void> update(double amount, {String? account}) async {
    final info = BalanceInfo(amount, DateTime.now());
    notifier.value = info;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kAmount, amount);
      await prefs.setString(_kUpdatedAt, info.updatedAt.toIso8601String());
    } catch (e) {
      debugPrint('BalanceStore.update: не сохранилось: $e');
    }
    await _pushToWidget(info, account);
  }

  /// отдаёт баланс виджету домашнего экрана и плитке (iOS и Android)
  static Future<void> _pushToWidget(BalanceInfo info, String? account) async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return;
    try {
      if (Platform.isIOS) await HomeWidget.setAppGroupId(_appGroup);
      await HomeWidget.saveWidgetData('balance_text', format(info.amount));
      final t = info.updatedAt;
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      await HomeWidget.saveWidgetData('balance_updated', '$hh:$mm');
      if (account != null && account.isNotEmpty) {
        await HomeWidget.saveWidgetData('account_text', account);
      }
      // токен биллинга - для кнопки «Обновить» на виджете и интента Сири:
      // они запрашивают баланс нативно, без запуска Dart (только iOS)
      await HomeWidget.saveWidgetData('bbb_token', await AuthStore().appToken);
      await HomeWidget.updateWidget(
          iOSName: _widgetKind, androidName: 'BalanceWidgetProvider');
    } catch (e) {
      debugPrint('Виджет баланса не обновлён: $e');
    }
  }

  /// сброс при выходе из аккаунта: чистим память, диск и виджет,
  /// чтобы баланс не оставался видимым после logout
  static Future<void> clear() async {
    notifier.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAmount);
      await prefs.remove(_kUpdatedAt);
    } catch (e) {
      debugPrint('BalanceStore.clear: $e');
    }
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return;
    try {
      if (Platform.isIOS) await HomeWidget.setAppGroupId(_appGroup);
      await HomeWidget.saveWidgetData('balance_text', '—');
      await HomeWidget.saveWidgetData('balance_updated', '');
      await HomeWidget.saveWidgetData('account_text', '');
      await HomeWidget.saveWidgetData('bbb_token', null);
      await HomeWidget.updateWidget(
          iOSName: _widgetKind, androidName: 'BalanceWidgetProvider');
    } catch (e) {
      debugPrint('Виджет баланса не очищен: $e');
    }
  }

  /// разбирает строку вида `1846.03`, `1 846,03`, `-12.5` в число
  static double? parseAmount(String raw) {
    final s = raw.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.');
    return double.tryParse(s);
  }

  /// «1 846,03 ₽» - формат для чипа в шапке
  static String format(double amount) {
    final sign = amount < 0 ? '−' : '';
    final abs = amount.abs();
    final whole = abs.truncate();
    final cents = ((abs - whole) * 100).round();
    final digits = whole.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final frac =
        cents == 0 ? '' : ',${cents.toString().padLeft(2, '0')}';
    return '$sign$buf$frac ₽';
  }
}
