import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// мост к нативной Live Activity замера скорости (iOS 16.2+).
/// На других платформах - молча ничего не делает
class SpeedLiveActivity {
  static const _ch = MethodChannel('ru.interra/liveactivity');

  static bool get _supported => !kIsWeb && Platform.isIOS;

  static Future<void> start() async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('start');
    } catch (e) {
      debugPrint('LiveActivity.start пропущен: $e');
    }
  }

  static Future<void> update({
    required String phase,
    double download = 0,
    double upload = 0,
    int ping = 0,
    double progress = 0,
  }) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('update', {
        'phase': phase,
        'download': download,
        'upload': upload,
        'ping': ping,
        'progress': progress,
      });
    } catch (_) {/* обновление не критично */}
  }

  static Future<void> end({
    double download = 0,
    double upload = 0,
    int ping = 0,
  }) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('end', {
        'phase': 'Готово',
        'download': download,
        'upload': upload,
        'ping': ping,
        'progress': 1.0,
      });
    } catch (_) {}
  }
}
