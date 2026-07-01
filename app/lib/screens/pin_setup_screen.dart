import 'package:flutter/material.dart';
import '../services/pin_lock.dart';
import '../widgets/pin_pad.dart';

/// Установка (или смена) код-пароля: ввод нового PIN и повтор для проверки.
/// Возвращает true через Navigator.pop, если PIN сохранён.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String? _first; // первый ввод; null — ещё на первом шаге

  Future<bool> _submit(String pin) async {
    if (_first == null) {
      setState(() => _first = pin);
      return true; // шаг «повторите код»
    }
    if (pin != _first) {
      // Не совпало — начинаем заново с встряской.
      setState(() => _first = null);
      return false;
    }
    await PinLock.setPin(pin);
    if (mounted) Navigator.of(context).pop(true);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final repeat = _first != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Код-пароль')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: PinPad(
            // Ключ сбрасывает введённые точки при переходе между шагами.
            key: ValueKey(repeat),
            title: repeat ? 'Повторите код' : 'Придумайте код',
            subtitle: repeat
                ? 'Введите тот же код ещё раз'
                : 'Он понадобится для входа, если Face ID недоступен',
            onSubmit: _submit,
          ),
        ),
      ),
    );
  }
}

/// Проверка текущего кода (например, перед отключением).
/// Возвращает true через Navigator.pop при верном вводе.
class PinVerifyScreen extends StatelessWidget {
  const PinVerifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Код-пароль')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: PinPad(
            title: 'Введите текущий код',
            onSubmit: (pin) async {
              final ok = await PinLock.verify(pin);
              if (ok && context.mounted) Navigator.of(context).pop(true);
              return ok;
            },
          ),
        ),
      ),
    );
  }
}
