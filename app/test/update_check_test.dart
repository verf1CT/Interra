import 'package:flutter_test/flutter_test.dart';
import 'package:lk_interra/services/update_check.dart';

void main() {
  group('UpdateCheck.isNewer', () {
    test('новее по мажору/минору/патчу', () {
      expect(UpdateCheck.isNewer('2.0.0', '1.9.9'), isTrue);
      expect(UpdateCheck.isNewer('1.1.0', '1.0.9'), isTrue);
      expect(UpdateCheck.isNewer('1.0.1', '1.0.0'), isTrue);
    });
    test('равные и старее — false', () {
      expect(UpdateCheck.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(UpdateCheck.isNewer('0.9.0', '1.0.0'), isFalse);
    });
    test('разная длина', () {
      expect(UpdateCheck.isNewer('1.0.0.1', '1.0.0'), isTrue);
      expect(UpdateCheck.isNewer('1.0', '1.0.0'), isFalse);
    });
  });
}
