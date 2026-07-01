import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'auth_store.dart';
import 'api_client.dart';
import 'notify_prefs.dart';

/// Обработчик push в фоне/при закрытом приложении. Должен быть top-level.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Системный трей сам покажет notification-сообщения; здесь дополнительная
  // обработка не требуется.
}

/// Сервис push-уведомлений (FCM) + показ локальных уведомлений на переднем плане.
class PushService {
  static final _local = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'interra_default',
    'Уведомления Интерра',
    description: 'Баланс, тариф, статусы заявок и сообщения провайдера',
    importance: Importance.high,
  );

  /// Инициализация: вызывать один раз после Firebase.initializeApp().
  /// Никогда не бросает — безопасно вызывать без await.
  static Future<void> init() async {
    try {
      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Локальные уведомления (для показа push, пришедших на переднем плане)
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _local.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // Push на переднем плане показываем сами через local notifications
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      // Регистрируем устройство и реагируем на обновление токена
      await registerCurrentToken();
      messaging.onTokenRefresh.listen((_) => registerCurrentToken());
    } catch (e) {
      debugPrint('PushService.init пропущен: $e');
    }
  }

  /// Получает текущий FCM-токен и регистрирует его на бэкенде вместе с логином.
  /// На iOS без APNs getToken может висеть/падать — оборачиваем в timeout/try.
  static Future<void> registerCurrentToken() async {
    try {
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 10));
      if (token == null) return;
      final phone = await AuthStore().phone;
      await ApiClient.registerDevice(
        token: token,
        clientLogin: phone,
        segments: await NotifyPrefs.enabledSegments(),
        prefs: await NotifyPrefs.prefsMap(),
      );
    } catch (e) {
      debugPrint('registerCurrentToken пропущен (нет APNs/бэкенда?): $e');
    }
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    await _local.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}
