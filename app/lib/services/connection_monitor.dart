import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// один замер связи: время и задержка в мс (null - связь недоступна)
class ConnSample {
  final DateTime at;
  final int? latencyMs;
  const ConnSample(this.at, this.latencyMs);
  bool get down => latencyMs == null;
}

/// период простоя (подряд идущие неудачные замеры)
class Outage {
  final DateTime start;
  final DateTime end;
  const Outage(this.start, this.end);
  Duration get duration => end.difference(start);
}

/// сводка по истории
typedef ConnStats = ({int? current, double? avg, int? worst, double uptime, int outages});

/// фоновый монитор качества связи: периодически замеряет задержку до интернета
/// и ведёт историю на диске, чтобы показать графиком качество связи и журнал
/// простоев. работает, пока приложение открыто (в фоне iOS/Android усыпляют
/// dart-таймеры) - на старте и при открытии экрана монитора замеры учащаются
class ConnectionMonitor {
  static const _fileName = 'conn_history.json';
  static const _maxAge = Duration(days: 7);
  static const _maxSamples = 4000;

  /// история замеров (по возрастанию времени) для UI
  static final ValueNotifier<List<ConnSample>> history = ValueNotifier([]);

  static bool _loaded = false;
  static bool _sampling = false;
  static Timer? _timer;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// поднимает историю с диска (один раз)
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString()) as List;
      final now = DateTime.now();
      final list = raw
          .map((e) => ConnSample(
              DateTime.fromMillisecondsSinceEpoch(e['t'] as int),
              (e['l'] as int) < 0 ? null : e['l'] as int))
          .where((s) => now.difference(s.at) < _maxAge)
          .toList();
      history.value = list;
    } catch (e) {
      debugPrint('ConnectionMonitor.load: $e');
    }
  }

  static Future<void> _save() async {
    try {
      final f = await _file();
      final data = history.value
          .map((s) => {'t': s.at.millisecondsSinceEpoch, 'l': s.latencyMs ?? -1})
          .toList();
      await f.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('ConnectionMonitor._save: $e');
    }
  }

  /// один замер: HEAD к лёгкому эндпоинту, меряем round-trip. недоступность
  /// подтверждаем запасным узлом, чтобы единичный сбой одного хоста не считать
  /// падением связи
  static Future<ConnSample> probe() async {
    final sw = Stopwatch()..start();
    for (final url in const [
      'https://www.gstatic.com/generate_204',
      'https://ya.ru',
    ]) {
      try {
        await http.head(Uri.parse(url)).timeout(const Duration(seconds: 5));
        return ConnSample(DateTime.now(), sw.elapsedMilliseconds);
      } catch (_) {
        // пробуем следующий узел
      }
    }
    return ConnSample(DateTime.now(), null);
  }

  /// делает замер и дописывает в историю
  static Future<void> sample() async {
    if (_sampling) return;
    _sampling = true;
    try {
      await load();
      final s = await probe();
      final now = DateTime.now();
      final list = [...history.value, s]
        ..removeWhere((x) => now.difference(x.at) > _maxAge);
      if (list.length > _maxSamples) {
        list.removeRange(0, list.length - _maxSamples);
      }
      history.value = list;
      await _save();
    } finally {
      _sampling = false;
    }
  }

  /// фоновые замеры с заданным периодом (сразу один + по таймеру)
  static void start({Duration every = const Duration(minutes: 3)}) {
    _timer?.cancel();
    sample();
    _timer = Timer.periodic(every, (_) => sample());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// периоды простоя (свежие сверху). простой - подряд идущие неудачные замеры;
  /// разрывы истории (приложение было закрыто) простоем НЕ считаем
  static List<Outage> outages() {
    final list = history.value;
    final res = <Outage>[];
    DateTime? start;
    DateTime? prev;
    for (final s in list) {
      if (s.down) {
        start ??= prev ?? s.at;
      } else if (start != null) {
        res.add(Outage(start, s.at));
        start = null;
      }
      prev = s.at;
    }
    if (start != null && prev != null) res.add(Outage(start, prev));
    return res.reversed.toList();
  }

  static ConnStats stats() {
    final list = history.value;
    final ups = list.where((s) => !s.down).map((s) => s.latencyMs!).toList();
    final avg = ups.isEmpty ? null : ups.reduce((a, b) => a + b) / ups.length;
    final worst = ups.isEmpty ? null : ups.reduce((a, b) => a > b ? a : b);
    final uptime = list.isEmpty ? 1.0 : ups.length / list.length;
    return (
      current: list.isEmpty ? null : list.last.latencyMs,
      avg: avg,
      worst: worst,
      uptime: uptime,
      outages: outages().length,
    );
  }
}
