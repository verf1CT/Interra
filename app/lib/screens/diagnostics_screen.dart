import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../theme.dart';
import '../services/analytics.dart';
import '../services/net_diagnostics.dart';

/// экран «Диагностика сети»: проверяет соединение шаг за шагом и говорит,
/// на чьей стороне проблема и что делать
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late final NetDiagnostics _diag =
      NetDiagnostics(onUpdate: () => setState(() {}));
  Verdict? _verdict;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _verdict = null;
    });
    final v = await _diag.run();
    Analytics.log('diagnostics_run', {'verdict': v.name});
    if (!mounted) return;
    setState(() {
      _verdict = v;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Диагностика сети')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _stepsCard(),
          const SizedBox(height: 18),
          if (_verdict != null) _verdictCard(_verdict!),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.refresh),
            label: Text(_running ? 'Проверяем…' : 'Проверить ещё раз'),
          ),
        ],
      ),
    );
  }

  Widget _stepsCard() => Container(
        clipBehavior: Clip.antiAlias,
        decoration: cardBox(),
        child: Column(
          children: [
            for (var i = 0; i < _diag.steps.length; i++) ...[
              if (i > 0)
                const Divider(
                    height: 1, thickness: 1, indent: 56, color: AppColors.line),
              _stepTile(_diag.steps[i]),
            ],
          ],
        ),
      );

  Widget _stepTile(DiagStep s) => ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: SizedBox(width: 28, height: 28, child: _stepIcon(s.status)),
        title: Text(s.title, style: const TextStyle(fontSize: 15)),
        trailing: s.latencyMs != null
            ? Text('${s.latencyMs} мс',
                style: const TextStyle(color: AppColors.inkFaint, fontSize: 12.5))
            : null,
      );

  Widget _stepIcon(StepStatus st) => switch (st) {
        StepStatus.pending => Icon(Icons.circle_outlined,
            size: 22, color: AppColors.line),
        StepStatus.running => const Padding(
            padding: EdgeInsets.all(3),
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: AppColors.brand),
          ),
        StepStatus.ok =>
          const Icon(Icons.check_circle_rounded, color: AppColors.ok, size: 24),
        StepStatus.fail =>
          const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 24),
      };

  Widget _verdictCard(Verdict v) {
    final (icon, color, title, advice) = switch (v) {
      Verdict.allOk => (
          Icons.check_circle_rounded,
          AppColors.ok,
          'Всё работает',
          'Соединение с интернетом и сервисами Интерры в порядке.',
        ),
      Verdict.noInternet => (
          Icons.router_rounded,
          AppColors.danger,
          'Нет доступа в интернет',
          'Похоже, проблема на вашей стороне. Перезагрузите роутер (выключите '
              'из розетки на 10 секунд), проверьте Wi-Fi и кабель. Если не '
              'помогло — позвоните в поддержку.',
        ),
      Verdict.providerIssue => (
          Icons.cloud_off_rounded,
          AppColors.accent,
          'Сервисы Интерры недоступны',
          'Интернет работает, но серверы провайдера не отвечают. Возможно, '
              'идут работы на сети — попробуйте позже или позвоните в '
              'поддержку.',
        ),
      Verdict.billingIssue => (
          Icons.cloud_off_rounded,
          AppColors.accent,
          'Личный кабинет временно недоступен',
          'Интернет и сайт работают, а сервер кабинета не отвечает. Обычно '
              'это ненадолго — попробуйте позже.',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(advice,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.45, color: AppColors.inkMute)),
          if (v == Verdict.noInternet || v == Verdict.providerIssue) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                Analytics.supportOpened('phone_diag');
                launchUrl(Uri(scheme: 'tel', path: AppConfig.supportPhone),
                    mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
              label: const Text('Позвонить: ${AppConfig.supportPhoneHuman}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
