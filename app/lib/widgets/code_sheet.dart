import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_sheets.dart';

/// шторка ввода кода из sms для формы биллинга. возвращает код или null
Future<String?> showCodeSheet(BuildContext context, {required String title, String? hint, required String button}) =>
    showAppSheet<String>(context, _CodeSheet(title: title, hint: hint, button: button));

class _CodeSheet extends StatefulWidget {
  final String title;
  final String? hint;
  final String button;
  const _CodeSheet({required this.title, this.hint, required this.button});

  @override
  State<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends State<_CodeSheet> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done(String? v) {
    // без этого на iOS цифровая клавиатура остаётся висеть после закрытия шторки
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(v?.trim());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.ink)),
          if (widget.hint != null) ...[
            const SizedBox(height: 6),
            Text(widget.hint!, style: TextStyle(fontSize: 14, color: p.inkMute, height: 1.35)),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(hintText: 'Код из sms'),
            onSubmitted: _done,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: FilledButton(onPressed: () => _done(_c.text), child: Text(widget.button)),
          ),
          const SizedBox(height: 4),
          SizedBox(height: 44, child: TextButton(onPressed: () => _done(null), child: const Text('Отмена'))),
        ],
      ),
    );
  }
}
