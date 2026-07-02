import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/services/connection_monitor.dart';

void main() {
  final t0 = DateTime(2026, 7, 3, 12, 0, 0);
  DateTime at(int min) => t0.add(Duration(minutes: min));

  tearDown(() => ConnectionMonitor.history.value = []);

  group('outages', () {
    test('нет падений - пустой список', () {
      ConnectionMonitor.history.value = [
        ConnSample(at(0), 20),
        ConnSample(at(1), 25),
        ConnSample(at(2), 22),
      ];
      expect(ConnectionMonitor.outages(), isEmpty);
    });

    test('одно падение между рабочими замерами', () {
      ConnectionMonitor.history.value = [
        ConnSample(at(0), 20),
        ConnSample(at(1), null),
        ConnSample(at(2), null),
        ConnSample(at(3), 30),
      ];
      final o = ConnectionMonitor.outages();
      expect(o.length, 1);
      // простой от последнего рабочего (min 0) до восстановления (min 3)
      expect(o.first.duration, const Duration(minutes: 3));
    });

    test('незакрытый простой в конце истории', () {
      ConnectionMonitor.history.value = [
        ConnSample(at(0), 20),
        ConnSample(at(1), null),
        ConnSample(at(5), null),
      ];
      final o = ConnectionMonitor.outages();
      expect(o.length, 1);
      expect(o.first.duration, const Duration(minutes: 5));
    });
  });

  group('stats', () {
    test('средний, худший и стабильность', () {
      ConnectionMonitor.history.value = [
        ConnSample(at(0), 10),
        ConnSample(at(1), 30),
        ConnSample(at(2), null),
        ConnSample(at(3), 20),
      ];
      final s = ConnectionMonitor.stats();
      expect(s.current, 20);
      expect(s.avg, 20); // (10+30+20)/3
      expect(s.worst, 30);
      expect(s.uptime, closeTo(0.75, 0.0001)); // 3 из 4
      expect(s.outages, 1);
    });

    test('пустая история - аптайм 100%', () {
      final s = ConnectionMonitor.stats();
      expect(s.current, isNull);
      expect(s.uptime, 1.0);
      expect(s.outages, 0);
    });
  });
}
