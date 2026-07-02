import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/analytics.dart';
import '../services/speed_test.dart';
import '../services/speed_live_activity.dart';

/// экран «Проверка скорости»: пинг, загрузка, отдача
class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> {
  SpeedPhase _phase = SpeedPhase.idle;
  SpeedResult _result = const SpeedResult();
  double _progress = 0;

  bool get _running =>
      _phase == SpeedPhase.ping ||
      _phase == SpeedPhase.download ||
      _phase == SpeedPhase.upload;

  DateTime _lastLive = DateTime.fromMillisecondsSinceEpoch(0);

  static String _phaseName(SpeedPhase p) => switch (p) {
        SpeedPhase.ping => 'Пинг',
        SpeedPhase.download => 'Загрузка',
        SpeedPhase.upload => 'Отдача',
        SpeedPhase.done => 'Готово',
        _ => 'Замер',
      };

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _result = const SpeedResult();
      _progress = 0;
    });
    await SpeedLiveActivity.start();
    final test = SpeedTest(onUpdate: (phase, sofar, progress) {
      if (!mounted) return;
      setState(() {
        _phase = phase;
        _result = sofar;
        _progress = progress;
      });
      // live Activity обновляем не чаще ~2.5 раз в секунду, чтобы не упереться
      // в системный троттлинг частых обновлений
      final now = DateTime.now();
      if (now.difference(_lastLive).inMilliseconds > 400) {
        _lastLive = now;
        SpeedLiveActivity.update(
          phase: _phaseName(phase),
          download: sofar.downloadMbps ?? 0,
          upload: sofar.uploadMbps ?? 0,
          ping: sofar.pingMs ?? 0,
          progress: progress,
        );
      }
    });
    final r = await test.run();
    await SpeedLiveActivity.end(
      download: r.downloadMbps ?? 0,
      upload: r.uploadMbps ?? 0,
      ping: r.pingMs ?? 0,
    );
    Analytics.log('speedtest_done', {
      if (r.pingMs != null) 'ping_ms': r.pingMs!,
      if (r.downloadMbps != null) 'down_mbps': r.downloadMbps!.round(),
      if (r.uploadMbps != null) 'up_mbps': r.uploadMbps!.round(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Проверка скорости')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _bigCard(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _metric('Пинг', _result.pingMs?.toString(), 'мс',
                      Icons.swap_vert_rounded)),
              const SizedBox(width: 12),
              Expanded(
                  child: _metric('Отдача', _fmt(_result.uploadMbps), 'Мбит/с',
                      Icons.upload_rounded)),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: Icon(_running ? Icons.speed_rounded : Icons.play_arrow_rounded),
            label: Text(_running ? _phaseLabel() : 'Начать замер'),
          ),
          const SizedBox(height: 14),
          Text(
            'Замер показывает фактическую скорость с этого телефона: '
            'по Wi-Fi она может быть ниже тарифной — влияет роутер и '
            'расстояние до него.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade500, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _phaseLabel() => switch (_phase) {
        SpeedPhase.ping => 'Меряем пинг…',
        SpeedPhase.download => 'Скачивание…',
        SpeedPhase.upload => 'Отдача…',
        _ => 'Начать замер',
      };

  static String? _fmt(double? mbps) {
    if (mbps == null) return null;
    return mbps >= 100 ? mbps.round().toString() : mbps.toStringAsFixed(1);
  }

  /// главная карточка - скорость скачивания крупно + прогресс
  Widget _bigCard() => Container(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brand, AppColors.accent],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.brand.withValues(alpha: 0.28),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            const Text('Загрузка',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              _fmt(_result.downloadMbps) ?? '—',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  height: 1),
            ),
            const Text('Мбит/с',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _running ? (_progress == 0 ? null : _progress) : 0,
                minHeight: 6,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          ],
        ),
      );

  Widget _metric(String title, String? value, String unit, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.brand, size: 22),
            const SizedBox(height: 8),
            Text(value ?? '—',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700)),
            Text('$title, $unit',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      );
}
