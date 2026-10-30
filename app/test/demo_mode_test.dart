import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lk_interra/services/demo_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DemoMode', () {
    test('defaults to true on first load (screenshot showcase build)', () async {
      await DemoMode.load();
      expect(DemoMode.isEnabled.value, true);
    });

    test('can be toggled and persisted in SharedPreferences', () async {
      await DemoMode.setEnabled(false);
      expect(DemoMode.isEnabled.value, false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('demo_screenshot_mode_enabled'), false);

      await DemoMode.load();
      expect(DemoMode.isEnabled.value, false);

      await DemoMode.setEnabled(true);
      expect(DemoMode.isEnabled.value, true);
    });

    test('demoCabinetData contains valid showcase data', () {
      final data = DemoMode.demoCabinetData;
      expect(data.balance, 1250.0);
      expect(data.account, '276997');
      expect(data.tariff, 'Комфорт 200');
      expect(data.needsPassportData, false);
      expect(data.address.isNotEmpty, true);
    });

    test('demoServices contains active tariff, TV and intercom', () {
      final services = DemoMode.demoServices;
      expect(services.length, 3);
      expect(services[0].name.contains('Комфорт 200'), true);
      expect(services[0].status, 'Активен');
    });

    test('availableTariffs contains modern telecom options', () {
      final tariffs = DemoMode.availableTariffs;
      expect(tariffs.length, 4);
      expect(tariffs.any((t) => t.isCurrent), true);
      expect(tariffs.firstWhere((t) => t.isCurrent).title, 'Комфорт 200');
    });

    test('demoPayments contains clean positive and negative balance operations', () {
      final payments = DemoMode.demoPayments;
      expect(payments.isNotEmpty, true);
      expect(payments.any((p) => p.amount > 0), true);
      expect(payments.any((p) => p.amount < 0), true);
    });

    test('demoSessions contains active and completed sessions', () {
      final sessions = DemoMode.demoSessions;
      expect(sessions.isNotEmpty, true);
      expect(sessions.any((s) => s.isActive), true);
      expect(sessions.any((s) => !s.isActive), true);
    });
  });
}
