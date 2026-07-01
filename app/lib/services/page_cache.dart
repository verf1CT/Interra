import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Кэш последнего успешно загруженного снимка кабинета — для показа без сети.
///
/// HTML складываем в файл (страница может быть крупной), исходный URL — в
/// SharedPreferences, чтобы при отрисовке снимка задать `baseUrl` (относительные
/// ссылки на ресурсы остаются корректными). Внешние CSS/картинки без сети не
/// подтянутся, но текстовое содержимое (баланс, тариф) остаётся читаемым.
class PageCache {
  static const _kUrl = 'cabinet_snapshot_url';
  static const _fileName = 'cabinet_snapshot.html';

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> save(String html, String url) async {
    try {
      await (await _file()).writeAsString(html, flush: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUrl, url);
    } catch (e) {
      debugPrint('PageCache.save: $e');
    }
  }

  /// Удаляет снимок (выход из аккаунта: в нём ФИО, адрес и баланс).
  static Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUrl);
    } catch (e) {
      debugPrint('PageCache.clear: $e');
    }
  }

  /// Возвращает `(html, baseUrl)` или null, если снимка ещё нет.
  static Future<(String, String?)?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final html = await f.readAsString();
      if (html.isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      return (html, prefs.getString(_kUrl));
    } catch (e) {
      debugPrint('PageCache.load: $e');
      return null;
    }
  }
}
