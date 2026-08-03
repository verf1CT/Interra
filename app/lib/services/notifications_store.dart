import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InAppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime receivedAt;
  final String? link;
  final bool isRead;

  InAppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.receivedAt,
    this.link,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'receivedAt': receivedAt.toIso8601String(),
        'link': link,
        'isRead': isRead,
      };

  factory InAppNotification.fromJson(Map<String, dynamic> json) =>
      InAppNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        receivedAt: DateTime.parse(json['receivedAt'] as String),
        link: json['link'] as String?,
        isRead: json['isRead'] as bool? ?? false,
      );

  InAppNotification copyWith({bool? isRead}) => InAppNotification(
        id: id,
        title: title,
        body: body,
        receivedAt: receivedAt,
        link: link,
        isRead: isRead ?? this.isRead,
      );
}

class NotificationsStore extends ChangeNotifier {
  static const _key = 'in_app_notifications_v1';
  static final NotificationsStore instance = NotificationsStore._();

  List<InAppNotification> _items = [];
  bool _loaded = false;

  NotificationsStore._();

  List<InAppNotification> get items => List.unmodifiable(_items);

  int get unreadCount => _items.where((n) => !n.isRead).length;

  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final List list = jsonDecode(raw) as List;
        _items = list
            .map((e) => InAppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> addNotification({
    required String title,
    required String body,
    String? link,
  }) async {
    await init();
    final item = InAppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      receivedAt: DateTime.now(),
      link: link,
      isRead: false,
    );

    _items.insert(0, item);
    // Храним максимум 50 последних уведомлений
    if (_items.length > 50) {
      _items = _items.sublist(0, 50);
    }

    await _save();
    notifyListeners();
  }

  Future<void> markAllAsRead() async {
    await init();
    _items = _items.map((e) => e.copyWith(isRead: true)).toList();
    await _save();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _items.clear();
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_items.map((e) => e.toJson()).toList());
      await prefs.setString(_key, raw);
    } catch (_) {}
  }
}
