import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// отправка дампа кабинета на компьютер разработчика в той же wi-fi сети,
/// где запущен приёмник app/tool/dump_server.dart. адрес вводится один раз
class DebugDump {
  static const _key = 'debug_dump_target';

  static Future<String?> savedTarget() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  /// «192.168.1.5:8787» или «192.168.1.5» (порт по умолчанию 8787)
  static Uri? targetUri(String target) {
    final t = target.trim().replaceFirst(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');
    if (t.isEmpty) return null;
    return Uri.tryParse('http://${t.contains(':') ? t : '$t:8787'}/dump');
  }

  static Future<bool> send(String target, String dump) async {
    final uri = targetUri(target);
    if (uri == null) return false;
    (await SharedPreferences.getInstance()).setString(_key, target.trim());
    try {
      final res = await http
          .post(uri, headers: {'Content-Type': 'text/plain; charset=utf-8'}, body: utf8.encode(dump))
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
