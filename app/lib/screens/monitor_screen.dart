import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/analytics.dart';
import '../services/connection_monitor.dart';

/// экран «качество связи»: живой пинг, график задержки за сутки и журнал простоев
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  @override
  void initState() {
    super.initState();
    Analytics.log('monitor_opened');
    // пока экран открыт - замеряем часто, для живой картины
    ConnectionMonitor.start(every: const Duration(seconds: 12));
  }

  @override
  void dispose() {
    // возвращаем редкие фоновые замеры
    ConnectionMonitor.start(every: const Duration(minutes: 3));
    super.dispose();
  }

  static Color _pingColor(int? ms) {
    if (ms == null) return AppColors.danger;
    if (ms < 60) return AppColors.ok;
    if (ms < 150) return AppColors.accent;
    return AppColors.danger;
  }

  static String _dur(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} с';
    if (d.inHours < 1) return '${d.inMinutes} мин';
    final h = d.inHours, m = d.inMinutes % 60;
    return m == 0 ? '$h ч' : '$h ч $m мин';
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    final sameDay = now.year == t.year && now.month == t.month && now.day == t.day;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    if (sameDay) return 'сегодня $hh:$mm';
    final yest = now.subtract(const Duration(days: 1));
    if (yest.year == t.year && yest.month == t.month && yest.day == t.day) {
      return 'вчера $hh:$mm';
    }
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Качество связи')),
      body: ValueListenableBuilder<List<ConnSample>>(
        valueListenable: ConnectionMonitor.history,
        builder: (context, all, _) {
          final stats = ConnectionMonitor.stats();
          final outages = ConnectionMonitor.outages();
          final cutoff = DateTime.now().subtract(const Duration(hours: 24));
          final day = all.where((s) => s.at.isAfter(cutoff)).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _liveCard(stats.current),
              const SizedBox(height: 16),
              _graphCard(day),
              const SizedBox(height: 16),
              _statsRow(stats),
              const SizedBox(height: 18),
              _sectionTitle('Простои'),
              _outagesCard(outages),
              const SizedBox(height: 14),
              Text(
                'мониторинг идёт, пока приложение открыто. чем чаще заходите - '
                'тем полнее история качества связи',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500, height: 1.4),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _liveCard(int? current) {
    final color = _pingColor(current);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.75)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.28),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Text(current == null ? 'нет связи' : 'сейчас',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            current == null ? '✕' : '$current',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 52,
                fontWeight: FontWeight.w800,
                height: 1),
          ),
          if (current != null)
            const Text('мс — задержка до интернета',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _graphCard(List<ConnSample> day) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Задержка за 24 часа',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            width: double.infinity,
            child: day.length < 2
                ? Center(
                    child: Text('накапливаем данные…',
                        style: TextStyle(color: Colors.grey.shade400)))
                : CustomPaint(painter: _LatencyPainter(day)),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(ConnStats s) {
    return Row(
      children: [
        Expanded(
            child: _stat('Средний', s.avg == null ? '—' : '${s.avg!.round()}', 'мс')),
        const SizedBox(width: 12),
        Expanded(child: _stat('Худший', s.worst == null ? '—' : '${s.worst}', 'мс')),
        const SizedBox(width: 12),
        Expanded(
            child: _stat('Стабильность',
                (s.uptime * 100).toStringAsFixed(s.uptime >= 0.9995 ? 0 : 1), '%')),
      ],
    );
  }

  Widget _outagesCard(List<Outage> outages) {
    if (outages.isEmpty) {
      return _card(
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.ok, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text('простоев не зафиксировано',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
            ),
          ],
        ),
      );
    }
    final show = outages.take(20).toList();
    return _card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < show.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, indent: 52, color: AppColors.line),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: const Icon(Icons.wifi_off_rounded,
                  color: AppColors.danger, size: 22),
              title: Text(_dur(show[i].duration),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: Text(_when(show[i].start)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String title, String value, String unit) => _card(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('$title, $unit',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
          ],
        ),
      );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4)),
          ],
        ),
        child: child,
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                letterSpacing: 0.5)),
      );
}

/// рисует ломаную задержки за сутки; разрывы истории (>15 мин между замерами)
/// не соединяем, неудачные замеры отмечаем красным у нижней оси
class _LatencyPainter extends CustomPainter {
  final List<ConnSample> samples;
  _LatencyPainter(this.samples);

  @override
  void paint(Canvas canvas, Size size) {
    final start = DateTime.now().subtract(const Duration(hours: 24));
    final total = DateTime.now().difference(start).inMilliseconds.toDouble();
    final ups = samples.where((s) => !s.down).map((s) => s.latencyMs!);
    final maxMs = ups.isEmpty ? 100 : ups.reduce((a, b) => a > b ? a : b);
    final maxY = (maxMs * 1.2).clamp(80, 500).toDouble();

    double x(DateTime t) =>
        (t.difference(start).inMilliseconds / total).clamp(0, 1) * size.width;
    double y(int ms) => size.height - (ms / maxY).clamp(0, 1) * size.height;

    // сетка
    final grid = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final gy = size.height * i / 4;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    final line = Paint()
      ..color = AppColors.brand
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    Path? path;
    DateTime? prev;
    for (final s in samples) {
      if (s.down) {
        // красная метка простоя у нижней оси
        canvas.drawCircle(Offset(x(s.at), size.height - 3), 2.5,
            Paint()..color = AppColors.danger);
        path = null;
        prev = s.at;
        continue;
      }
      final p = Offset(x(s.at), y(s.latencyMs!));
      final gap = prev == null || s.at.difference(prev).inMinutes > 15;
      if (gap || path == null) {
        if (path != null) canvas.drawPath(path, line);
        path = Path()..moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      prev = s.at;
    }
    if (path != null) canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_LatencyPainter old) => old.samples != samples;
}
