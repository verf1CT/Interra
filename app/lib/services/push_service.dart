import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'auth_store.dart';
import 'api_client.dart';
import 'notify_prefs.dart';
import 'notifications_store.dart';
import 'quick_actions_service.dart';
import '../screens/diagnostics_screen.dart';
import '../screens/notifications_history_screen.dart';

/// обработчик push в фоне/при закрытом приложении. должен быть top-level
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // системный трей сам покажет notification-сообщения; здесь дополнительная
  // обработка не требуется
}

/// сервис push-уведомлений (FCM) + показ локальных уведомлений на переднем плане
class PushService {
  static final _local = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'interra_default',
    'Уведомления Интерра',
    description: 'Баланс, тариф, статусы заявок и сообщения провайдера',
    importance: Importance.high,
  );

  /// инициализация: вызывать один раз после Firebase.initializeApp().
  /// Никогда не бросает - безопасно вызывать без await
  static Future<void> init() async {
    try {
      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // локальные уведомления (для показа push, пришедших на переднем плане)
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _local.initialize(
        settings:
            const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: _onLocalTap,
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // push на переднем плане показываем сами через local notifications
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      // тап по пушу с data.link (rich push из панели) → открываем ссылку.
      // Из фона/закрытого состояния и когда приложение было убито
      FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _openFromMessage(initial);

      // регистрируем устройство и реагируем на обновление токена
      await registerCurrentToken();
      messaging.onTokenRefresh.listen((_) => registerCurrentToken());

      // подписка на общую тему - канал массовых рассылок «на всех» (через
      // FCM topic, не зависит от таргетинга по сегментам в консоли Firebase)
      await _subscribeAll(messaging);
    } catch (e) {
      debugPrint('PushService.init пропущен: $e');
    }
  }

  /// подписка на тему массовых рассылок. best-effort: на iOS без APNs
  /// подписка может падать, поэтому не даём ей ломать остальную инициализацию
  static Future<void> _subscribeAll(FirebaseMessaging messaging) async {
    try {
      await messaging.subscribeToTopic('all');
    } catch (e) {
      debugPrint('subscribeToTopic(all) пропущен: $e');
    }
  }

  /// получает текущий FCM-токен и регистрирует его на бэкенде вместе с логином.
  /// На iOS без APNs getToken может висеть/падать - оборачиваем в timeout/try
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

  /// тап по системному пушу (фон/закрытое приложение): открываем ссылку и
  /// отмечаем открытие рассылки в аналитике бэкенда
  static Future<void> _openFromMessage(RemoteMessage message) async {
    final bid = message.data['bid'];
    if (bid is String && bid.isNotEmpty) ApiClient.reportOpened(bid);

    final screen = message.data['screen'];
    if (screen is String && screen.isNotEmpty) {
      _navigateToScreen(screen);
      return;
    }
    await _openLink(message.data['link']);
  }

  /// тап по локальному уведомлению (показанному на переднем плане):
  /// payload — JSON строка с link и screen
  static void _onLocalTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      final screen = data['screen'] as String?;
      if (screen != null && screen.isNotEmpty) {
        _navigateToScreen(screen);
        return;
      }
      _openLink(data['link'] as String?);
    } catch (_) {
      // обратная совместимость: payload = простая ссылка
      _openLink(response.payload);
    }
  }

  /// Deep-link навигация по имени экрана из push data
  static void _navigateToScreen(String screen) {
    final nav = QuickActionsService.navigatorKey.currentState;
    if (nav == null) return;

    switch (screen) {
      case 'diagnostics':
        nav.push(MaterialPageRoute(
          builder: (_) => const DiagnosticsScreen(),
          settings: const RouteSettings(name: 'diagnostics'),
        ));
      case 'settings':
        QuickActionsService.route('action_settings');
      case 'support':
        QuickActionsService.route('action_support');
      case 'payment':
        QuickActionsService.route('action_pay');
      case 'notifications':
        nav.push(MaterialPageRoute(
          builder: (_) => const NotificationsHistoryScreen(),
          settings: const RouteSettings(name: 'notifications'),
        ));
      default:
        debugPrint('Неизвестный deep-link экран: $screen');
    }
  }

  /// открывает ссылку во внешнем браузере. только https — чтобы пуш не мог
  /// открыть произвольную схему
  static Future<void> _openLink(String? link) async {
    try {
      if (link == null || !link.startsWith('https://')) return;
      final uri = Uri.tryParse(link);
      if (uri == null) return;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('открытие ссылки из push пропущено: $e');
    }
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;

    final link = message.data['link'];
    final payloadLink = (link is String && link.startsWith('https://')) ? link : null;
    final screen = message.data['screen'];

    // JSON payload для onLocalTap — содержит и link, и screen
    final payloadJson = jsonEncode({
      if (payloadLink != null) 'link': payloadLink,
      if (screen is String && screen.isNotEmpty) 'screen': screen,
    });

    if (n.title != null || n.body != null) {
      NotificationsStore.instance.addNotification(
        title: n.title ?? 'Уведомление',
        body: n.body ?? '',
        link: payloadLink,
      );
    }

    // rich-картинка (Android): скачиваем и показываем big-picture; при любой
    // ошибке тихо откатываемся к обычному текстовому уведомлению
    StyleInformation? style;
    final imageUrl = n.android?.imageUrl;
    if (imageUrl != null && imageUrl.startsWith('https://')) {
      try {
        final res = await http
            .get(Uri.parse(imageUrl))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          style = BigPictureStyleInformation(
            ByteArrayAndroidBitmap(res.bodyBytes),
            contentTitle: n.title,
            summaryText: n.body,
          );
        }
      } catch (e) {
        debugPrint('картинка push не загружена: $e');
      }
    }

    await _local.show(
      id: n.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: style,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payloadJson,
    );
  }
}
