import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lk_interra/services/demo_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DemoMode', () {
    test('defaults to false on first load (production build)', () async {
      await DemoMode.load();
      expect(DemoMode.isEnabled.value, false);
    });

    test('can be toggled and persisted in SharedPreferences', () async {
      await DemoMode.setEnabled(false);
      expect(DemoMode.isEnabled.value, false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('qa_secret_demo_enabled_v2'), false);

      await DemoMode.load();
      expect(DemoMode.isEnabled.value, false);

      await DemoMode.setEnabled(true);
      expect(DemoMode.isEnabled.value, true);
    });

    test('demoCabinetData contains valid showcase data', () {
      final data = DemoMode.demoCabinetData;
      expect(data.balance, 1250.0);
      expect(data.account, '123456');
      expect(data.fullName, 'Иванов Иван Иванович');
      expect(data.tariff, 'Месяц 100М');
      expect(data.needsPassportData, false);
      expect(data.address.isNotEmpty, true);
    });

    test('demoServices - только действующий тариф, как отдаёт биллинг', () {
      final services = DemoMode.demoServices;
      expect(services.single.name, 'Месяц 100М');
      expect(services.single.cost, endsWith('/ мес'));
    });

    test('demoPayments contains clean positive and negative balance operations', () {
      final payments = DemoMode.demoPayments;
      expect(payments.isNotEmpty, true);
      expect(payments.any((p) => p.amount > 0), true);
      expect(payments.any((p) => p.amount < 0), true);
    });
  });
}
