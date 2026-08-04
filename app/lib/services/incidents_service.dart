import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class Incident {
  final String id;
  final String title;
  final String? description;
  final String type; // 'incident' or 'planned_work'
  final String status; // 'active' or 'resolved'
  final String? affectedArea;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  Incident({
    required this.id,
    required this.title,
    this.description,
    required this.type,
    required this.status,
    this.affectedArea,
    required this.createdAt,
    this.resolvedAt,
  });

  factory Incident.fromJson(Map<String, dynamic> json) {
    return Incident(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      type: json['type'] as String,
      status: json['status'] as String,
      affectedArea: json['affectedArea'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      resolvedAt: json['resolvedAt'] != null
          ? DateTime.parse(json['resolvedAt'] as String).toLocal()
          : null,
    );
  }
}

class IncidentsService {
  static Future<List<Incident>> fetchActiveIncidents() async {
    try {
      final res = await http
          .get(Uri.parse(AppConfig.incidentsUrl))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(res.bodyBytes));
        return data.map((e) => Incident.fromJson(e)).toList();
      }
      throw Exception('Ошибка загрузки: ${res.statusCode}');
    } catch (e) {
      throw Exception('Не удалось загрузить инциденты: $e');
    }
  }

  static Future<List<Incident>> fetchHistoryIncidents() async {
    try {
      final res = await http
          .get(Uri.parse('${AppConfig.incidentsUrl}/history'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(res.bodyBytes));
        return data.map((e) => Incident.fromJson(e)).toList();
      }
      throw Exception('Ошибка загрузки истории: ${res.statusCode}');
    } catch (e) {
      throw Exception('Не удалось загрузить историю инцидентов: $e');
    }
  }
}
