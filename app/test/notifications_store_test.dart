import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lk_interra/services/notifications_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('NotificationsStore add and clear notifications', () async {
    final store = NotificationsStore.instance;
    await store.clearAll();

    expect(store.items.isEmpty, isTrue);
    expect(store.unreadCount, equals(0));

    await store.addNotification(
      title: 'Тест',
      body: 'Текст сообщения',
      link: 'https://interra.ru/pay',
    );

    expect(store.items.length, equals(1));
    expect(store.items.first.title, equals('Тест'));
    expect(store.items.first.link, equals('https://interra.ru/pay'));

    await store.markAllAsRead();
    expect(store.unreadCount, equals(0));

    await store.clearAll();
    expect(store.items.isEmpty, isTrue);
  });
}
