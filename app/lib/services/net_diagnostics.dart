import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Статус одного шага диагностики.
enum StepStatus { pending, running, ok, fail }

/// Итоговый вердикт: где проблема и что делать.
enum Verdict {
  allOk, // всё работает
  noInternet, // нет сети вообще — роутер/Wi-Fi/кабель
  providerIssue, // интернет есть, а сервисы Интерры недоступны
  billingIssue, // сайт жив, лежит только биллинг (кабинет)
}

class DiagStep {
  final String title;
  final Future<void> Function() probe;
  StepStatus status = StepStatus.pending;
  int? latencyMs;
  DiagStep(this.title, this.probe);
}

/// Диагностика соединения: последовательные проверки от «есть ли интернет»
/// до «жив ли кабинет», с замером времени ответа.
///
/// Все проверки — чистый Dart (DNS + HTTPS), без нативных плагинов. До шлюза
/// (роутера) без нативного кода не достучаться, поэтому «нет интернета»
/// диагностируем по совокупности: не резолвится DNS и не отвечают внешние узлы.
class NetDiagnostics {
  static const _timeout = Duration(seconds: 6);

  final List<DiagStep> steps;
  final void Function() onUpdate;

  bool _internetOk = false;
  bool _siteOk = false;
  bool _billingOk = false;

  NetDiagnostics({required this.onUpdate})
      : steps = [] {
    steps.addAll([
      DiagStep('Интернет-соединение', _probeInternet),
      DiagStep('DNS (адреса сайтов)', _probeDns),
      DiagStep('Сайт Интерры', _probeSite),
      DiagStep('Личный кабинет (биллинг)', _probeBilling),
    ]);
  }

  /// Прогоняет все шаги по очереди. Возвращает вердикт.
  Future<Verdict> run() async {
    _internetOk = _siteOk = _billingOk = false;
    for (final s in steps) {
      s.status = StepStatus.pending;
      s.latencyMs = null;
    }
    onUpdate();

    for (final s in steps) {
      s.status = StepStatus.running;
      onUpdate();
      final sw = Stopwatch()..start();
      try {
        await s.probe().timeout(_timeout);
        s.status = StepStatus.ok;
        s.latencyMs = sw.elapsedMilliseconds;
      } catch (e) {
        s.status = StepStatus.fail;
        debugPrint('Диагностика «${s.title}»: $e');
      }
      onUpdate();
    }

    if (!_internetOk) return Verdict.noInternet;
    if (!_siteOk && !_billingOk) return Verdict.providerIssue;
    if (!_billingOk) return Verdict.billingIssue;
    return Verdict.allOk;
  }

  /// Внешний интернет: лёгкий эндпоинт Google (204 без тела). Если он вдруг
  /// заблокирован — пробуем Яндекс.
  Future<void> _probeInternet() async {
    try {
      await http
          .head(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      await http.head(Uri.parse('https://ya.ru'));
    }
    _internetOk = true;
  }

  Future<void> _probeDns() async {
    final r = await InternetAddress.lookup('interra.ru');
    if (r.isEmpty) throw Exception('пустой ответ DNS');
  }

  Future<void> _probeSite() async {
    final res = await http.head(Uri.parse('https://interra.ru/'));
    if (res.statusCode >= 500) throw Exception('HTTP ${res.statusCode}');
    _siteOk = true;
  }

  Future<void> _probeBilling() async {
    // Корень биллинга; важно не «200», а что сервер вообще отвечает.
    final res = await http.get(Uri.parse('https://stat.interra.ru/'));
    if (res.statusCode >= 500) throw Exception('HTTP ${res.statusCode}');
    _billingOk = true;
  }
}
