import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lk_interra/services/biometric.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('первый запуск - замок нужен даже при «никогда»', () async {
    await Biometric.setLockDelayMs(Biometric.lockDelayNever);
    // ещё ни разу не разблокировали
    expect(await Biometric.withinGracePeriod, isFalse);
  });

  test('после разблокировки «никогда» больше не спрашивает', () async {
    await Biometric.setLockDelayMs(Biometric.lockDelayNever);
    await Biometric.markUnlocked();
    expect(await Biometric.withinGracePeriod, isTrue);
  });

  test('«сразу» всегда спрашивает даже после разблокировки', () async {
    await Biometric.setLockDelayMs(0);
    await Biometric.markUnlocked();
    expect(await Biometric.withinGracePeriod, isFalse);
  });

  test('30 минут: сразу после разблокировки замок можно не показывать', () async {
    await Biometric.setLockDelayMs(Biometric.defaultLockDelayMs);
    await Biometric.markUnlocked();
    expect(await Biometric.withinGracePeriod, isTrue);
  });
}
