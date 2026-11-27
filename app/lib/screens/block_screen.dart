import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_store.dart';
import '../services/cabinet_parser.dart';
import '../services/demo_mode.dart';
import '../theme.dart';
import '../widgets/app_sheets.dart';
import '../widgets/motion_kit.dart';

/// блокировка интернета со страницы aaaprcn: долгосрочная (отпуск) и
/// краткосрочная (родительский контроль по коду из sms). страницу показываем
/// как её отдаёт биллинг - разделы, текст и кнопки, поэтому состояния, которых
/// мы ещё не видели (снять блок, ввести код), тоже появятся сами
class BlockScreen extends StatefulWidget {
  const BlockScreen({super.key});

  @override
  State<BlockScreen> createState() => _BlockScreenState();
}

class _BlockScreenState extends State<BlockScreen> {
  bool _loading = true;
  List<BlockSection> _sections = const [];

  /// что биллинг ответил на последнюю кнопку
  List<String> _reply = const [];
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    String? html;
    if (DemoMode.isEnabled.value) {
      html = _demoPage;
    } else {
      try {
        final token = await AuthStore().appToken;
        if (token != null) html = await CabinetParser.fetchBlockPage(token);
      } catch (e) {
        debugPrint('блокировка не загрузилась: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _sections = html == null ? const [] : parseBlockPage(html);
      _loading = false;
    });
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// код, введённый последним: биллинг может спросить его ещё раз в следующей форме
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _press(BlockSection section, BlockAction action) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (DemoMode.isEnabled.value) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('В демо-режиме блокировка недоступна')));
      return;
    }
    final code = _code.text.trim();
    if (action.needsCode && code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите код из sms')));
      return;
    }
    // своё подтверждение - только перед блоком и запросом sms. на остальные
    // кнопки («Да», «Нет», «Отключить интернет» с кодом) биллинг спрашивает сам
    final label = action.label.toLowerCase();
    final long = label.contains('заблокировать');
    final sms = label.contains('код') && !action.needsCode;
    if (long || sms) {
      final ok = await showConfirmSheet(
        context,
        icon: sms ? Icons.sms_outlined : Icons.lock_outline_rounded,
        title: _cap(action.label),
        message: long
            ? 'Интернет отключится, пока блокировка не снята. Пользоваться ей можно не чаще раза в три месяца, '
                'а если блок продлится больше двух месяцев, тариф отключится'
            : 'Биллинг пришлёт sms с кодом на номер из кабинета',
        confirmLabel: _cap(action.label),
        danger: long,
      );
      if (!ok || !mounted) return;
    }
    await _submit(action, action.needsCode ? code : null);
  }

  Future<void> _submit(BlockAction action, String? code) async {
    setState(() => _busy = action.label);
    String? html;
    try {
      final token = await AuthStore().appToken;
      if (token != null) html = await CabinetParser.submitBlockAction(token, action, code: code);
    } catch (e) {
      debugPrint('кнопка блокировки: $e');
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    final before = _sections;
    final after = html == null ? const <BlockSection>[] : parseBlockPage(html);
    setState(() {
      _busy = null;
      _reply = html == null
          ? const ['Биллинг не ответил. Проверьте интернет и попробуйте ещё раз']
          : newBlockLines(before, after);
      // ответ - это та же страница в новом состоянии; если в нём нет кнопок,
      // перечитываем раздел
      if (after.any((s) => s.actions.isNotEmpty)) _sections = after;
    });
    if (after.every((s) => s.actions.isEmpty)) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Блокировка интернета')),
      body: _body(),
    );
  }

  Widget _body() {
    final p = context.p;
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: const [
          SkeletonBox(width: double.infinity, height: 200, radius: 20),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 160, radius: 20),
        ],
      );
    }
    if (_sections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Не удалось открыть блокировку',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.ink)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          if (_reply.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in _reply)
                    Text(_cap(l), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final s in _sections) ...[
            _section(s),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _section(BlockSection s) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: cardBox(context, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.title.isNotEmpty)
            Text(s.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.ink)),
          for (final l in s.lines) ...[
            const SizedBox(height: 6),
            Text(l, style: TextStyle(fontSize: 13.5, color: p.inkMute, height: 1.4)),
          ],
          if (s.warning != null) ...[
            const SizedBox(height: 6),
            Text(s.warning!,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.danger, height: 1.4)),
          ],
          for (final group in _forms(_withResend(s.actions))) ...[
            if (group.first.hint != null) ...[
              const SizedBox(height: 12),
              // биллинг пишет ошибку кода в той же форме: её выделяем
              for (final line in group.first.hint!.split('\n'))
                Text(_cap(line),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: line.toLowerCase().contains('невер') ? AppColors.danger : p.ink,
                        height: 1.35)),
            ],
            if (group.first.needsCode) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _code,
                maxLength: group.first.codeLength,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: InputDecoration(
                  hintText: group.first.codeLength != null
                      ? '${group.first.codeLength} цифр из sms родительского контроля'
                      : 'Код из sms',
                  counterText: '',
                ),
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              ),
            ],
            for (final a in group) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: _busy == a.label
                    ? const Center(child: CircularProgressIndicator(color: AppColors.brand))
                    : OutlinedButton(
                        onPressed: _busy != null ? null : () => _press(s, a),
                        child: Text(_cap(a.label), textAlign: TextAlign.center),
                      ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// пока код родительского контроля не введён, биллинг держит форму кода и
/// убирает кнопку «получить код». потерял sms - выхода нет, поэтому шлём тот
/// же запрос, что и та кнопка: если биллинг его примет, придёт новая sms
List<BlockAction> _withResend(List<BlockAction> actions) {
  final waitsCode = actions.any((a) => a.needsCode);
  final canRequest = actions.any((a) => a.fields.containsKey('isms'));
  if (!waitsCode || canRequest) return actions;
  return [
    ...actions,
    const BlockAction(
      label: 'прислать код ещё раз',
      fields: {'isms': 'получить код родительского контроля'},
      form: -1,
    ),
  ];
}

/// кнопки по формам, в порядке страницы
List<List<BlockAction>> _forms(List<BlockAction> actions) {
  final out = <List<BlockAction>>[];
  for (final a in actions) {
    if (out.isNotEmpty && out.last.first.form == a.form) {
      out.last.add(a);
    } else {
      out.add([a]);
    }
  }
  return out;
}

// страница из дампа для демо-режима и скриншотов
const _demoPage = """
<td id="aaatds"><b class="font-l">Долгосрочная блокировка</b><br>
<p>Данная блокировка предназначена для особых редких случаев, таких, например, как отпуск.<br> Ей можно пользоваться не чаще, чем раз в три месяца.<br> Время окончания тарифа в данном случае пересчитывается (к нему добавляются дни, проведённые в блоке).<br> Действующий тариф будет автоматически отключен, если продолжительность блокировки составит более двух месяцев.</p><br><form method="post" action=""><input type="hidden" name="sets" value="down"><input class="btn" type="submit" name="btn" value="заблокировать учётную запись"></form><br><br><h2>Краткосрочная блокировка</h2>Данной блокировкой можно пользоваться сколь угодно часто.<br> Её можно использовать, например, для родительского контроля.<br><b class="p">Время окончания тарифа при таком типе блокировки не пересчитывается.</b><br><form action="" method="post">для активации услуги нужно <input class="btn" type="submit" name="isms" value="получить код родительского контроля"> в смс</form></td>""";
