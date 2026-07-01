import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Результаты замера скорости.
class SpeedResult {
  final int? pingMs;
  final double? downloadMbps;
  final double? uploadMbps;
  const SpeedResult({this.pingMs, this.downloadMbps, this.uploadMbps});

  SpeedResult copyWith({int? pingMs, double? downloadMbps, double? uploadMbps}) =>
      SpeedResult(
        pingMs: pingMs ?? this.pingMs,
        downloadMbps: downloadMbps ?? this.downloadMbps,
        uploadMbps: uploadMbps ?? this.uploadMbps,
      );
}

/// Этап замера — для подписи под индикатором.
enum SpeedPhase { idle, ping, download, upload, done, error }

/// Замер скорости соединения: пинг до биллинга Интерры, скачивание и отдача
/// через тестовые эндпоинты Cloudflare (стабильные, без ключей, гоняют мусор).
///
/// Числа — оценка «как быстро работает интернет с этого телефона сейчас»
/// (Wi-Fi/LTE влияет), а не паспортная скорость тарифа.
class SpeedTest {
  static const _down = 'https://speed.cloudflare.com/__down?bytes=';
  static const _up = 'https://speed.cloudflare.com/__up';

  /// Сколько байт качаем/льём. 20 МБ вниз и 8 МБ вверх достаточно для оценки
  /// и не съедает мобильный трафик впустую.
  static const int _downloadBytes = 20 * 1000 * 1000;
  static const int _uploadBytes = 8 * 1000 * 1000;
  static const Duration _cap = Duration(seconds: 12);

  final void Function(SpeedPhase phase, SpeedResult sofar, double progress)
      onUpdate;

  SpeedTest({required this.onUpdate});

  Future<SpeedResult> run() async {
    var result = const SpeedResult();
    final client = http.Client();
    try {
      onUpdate(SpeedPhase.ping, result, 0);
      result = result.copyWith(pingMs: await _ping(client));
      onUpdate(SpeedPhase.download, result, 0);
      result = result.copyWith(downloadMbps: await _download(client, result));
      onUpdate(SpeedPhase.upload, result, 0);
      result = result.copyWith(uploadMbps: await _upload(client, result));
      onUpdate(SpeedPhase.done, result, 1);
      return result;
    } catch (e) {
      debugPrint('SpeedTest: $e');
      onUpdate(SpeedPhase.error, result, 0);
      return result;
    } finally {
      client.close();
    }
  }

  /// Медиана HTTP-round-trip до биллинга. Первый запрос выбрасываем — в нём
  /// TLS-хендшейк; остальные идут по уже открытому соединению.
  Future<int> _ping(http.Client client) async {
    final uri = Uri.parse(AppConfig.bbbUrl);
    final samples = <int>[];
    for (var i = 0; i < 5; i++) {
      final sw = Stopwatch()..start();
      await client.get(uri).timeout(const Duration(seconds: 6));
      if (i > 0) samples.add(sw.elapsedMilliseconds);
    }
    samples.sort();
    return samples[samples.length ~/ 2];
  }

  Future<double> _download(http.Client client, SpeedResult sofar) async {
    final req =
        http.Request('GET', Uri.parse('$_down$_downloadBytes'));
    final res = await client.send(req).timeout(const Duration(seconds: 10));
    final sw = Stopwatch()..start();
    var received = 0;
    await for (final chunk in res.stream.timeout(_cap)) {
      received += chunk.length;
      onUpdate(SpeedPhase.download,
          sofar.copyWith(downloadMbps: _mbps(received, sw)),
          min(received / _downloadBytes, 1));
      if (sw.elapsed > _cap) break;
    }
    return _mbps(received, sw);
  }

  Future<double> _upload(http.Client client, SpeedResult sofar) async {
    // Псевдослучайный мусор, чтобы транспорт ничего не сжал по пути.
    final rnd = Random(42);
    final chunk =
        Uint8List.fromList(List.generate(64 * 1024, (_) => rnd.nextInt(256)));
    final chunks = _uploadBytes ~/ chunk.length;

    final sw = Stopwatch()..start();
    var sent = 0;
    final req = http.StreamedRequest('POST', Uri.parse(_up))
      ..contentLength = chunks * chunk.length;
    // Кормим тело порциями, попутно репортя прогресс.
    unawaited(() async {
      for (var i = 0; i < chunks; i++) {
        req.sink.add(chunk);
        sent += chunk.length;
        onUpdate(SpeedPhase.upload,
            sofar.copyWith(uploadMbps: _mbps(sent, sw)), sent / _uploadBytes);
        if (sw.elapsed > _cap) break;
      }
      await req.sink.close();
    }());
    await client.send(req).timeout(_cap * 2);
    return _mbps(sent, sw);
  }

  static double _mbps(int bytes, Stopwatch sw) {
    final s = sw.elapsedMicroseconds / 1e6;
    if (s <= 0) return 0;
    return bytes * 8 / 1e6 / s;
  }
}
