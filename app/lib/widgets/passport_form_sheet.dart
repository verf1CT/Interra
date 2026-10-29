import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../services/auth_store.dart';
import '../services/cabinet_parser.dart';

class PassportFormSheet extends StatefulWidget {
  final VoidCallback? onSaved;

  const PassportFormSheet({super.key, this.onSaved});

  static Future<void> show(BuildContext context, {VoidCallback? onSaved}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PassportFormSheet(onSaved: onSaved),
    );
  }

  @override
  State<PassportFormSheet> createState() => _PassportFormSheetState();
}

class _PassportFormSheetState extends State<PassportFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _passportController = TextEditingController();
  final _issueDateController = TextEditingController();
  final _issuedByController = TextEditingController();
  final _birthDateController = TextEditingController();
  
  bool _agreed = false;
  bool _submitting = false;
  bool _openingWeb = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passportController.dispose();
    _issueDateController.dispose();
    _issuedByController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  Future<void> _openOnWeb() async {
    setState(() => _openingWeb = true);
    try {
      final token = await AuthStore().appToken;
      if (token == null) throw Exception('auth_expired');
      final url = await CabinetParser.getTariffsWebUrl(token);
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        setState(() => _errorMessage = 'Не удалось сформировать ссылку для входа в кабинет');
      }
    } catch (_) {
      setState(() => _errorMessage = 'Ошибка сессии. Попробуйте перезайти в приложение.');
    } finally {
      if (mounted) setState(() => _openingWeb = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      setState(() => _errorMessage = 'Необходимо согласиться с условиями договора');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final token = await AuthStore().appToken;
      if (token == null) throw Exception('auth_expired');

      final ok = await CabinetParser.submitPassportData(
        appToken: token,
        passportSeriesNumber: _passportController.text.trim(),
        issueDate: _issueDateController.text.trim(),
        issuedBy: _issuedByController.text.trim(),
        birthDate: _birthDateController.text.trim(),
      );

      if (mounted) {
        setState(() => _submitting = false);
        if (ok) {
          Navigator.of(context).pop();
          widget.onSaved?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Паспортные данные успешно сохранены!'),
              backgroundColor: AppColors.brand,
            ),
          );
        } else {
          setState(() => _errorMessage =
              'Сервер биллинга не сохранил данные (возможно, формат отклонён). Нажмите «Заполнить на сайте» ниже, чтобы открыть официальную форму.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = 'Ошибка отправки данных. Попробуйте открыть форму на сайте.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: context.p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Выбор тарифа',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: context.p.ink,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Блок предупреждения как на сайте (Скриншот 3)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Не хватает учётных данных.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Для выбора тарифа необходимо ввести паспортные данные.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Даты и серия/номер паспорта вводятся в строгом соответствии с указанным шаблоном.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.p.inkMute,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Поле 1: серия и номер
              Text(
                'Десять цифр, серия и номер паспорта СССС-НННННН:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.p.ink),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _passportController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'СССС-НННННН',
                  filled: true,
                  fillColor: context.p.card,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 10) {
                    return 'Введите 10 цифр серии и номера (СССС-НННННН)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Поле 2: дата когда выдан
              Text(
                'Дата когда выдан паспорт ДД.ММ.ГГГГ:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.p.ink),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _issueDateController,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  hintText: 'ДД.ММ.ГГГГ',
                  filled: true,
                  fillColor: context.p.card,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 8) {
                    return 'Введите дату выдачи (ДД.ММ.ГГГГ)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Поле 3: кем выдан
              Text(
                'Кем выдан паспорт:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.p.ink),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _issuedByController,
                decoration: InputDecoration(
                  hintText: 'Например, Отделом УФМС России...',
                  filled: true,
                  fillColor: context.p.card,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 3) {
                    return 'Укажите орган, выдавший паспорт';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Поле 4: дата рождения
              Text(
                'Дата рождения абонента ДД.ММ.ГГГГ:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.p.ink),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _birthDateController,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  hintText: 'ДД.ММ.ГГГГ',
                  filled: true,
                  fillColor: context.p.card,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 8) {
                    return 'Введите дату рождения (ДД.ММ.ГГГГ)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Чекбокс согласия
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _agreed,
                    activeColor: AppColors.brand,
                    onChanged: (v) => setState(() => _agreed = v ?? false),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final uri = Uri.parse('https://interra.ru/help/');
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'С '),
                            TextSpan(
                              text: 'Соглашением о предоставлении услуг',
                              style: TextStyle(
                                color: AppColors.brand,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            const TextSpan(text: ' ознакомлен'),
                          ],
                        ),
                        style: TextStyle(fontSize: 13, color: context.p.ink),
                      ),
                    ),
                  ),
                ],
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w500),
                ),
              ],
              const SizedBox(height: 16),

              // Кнопка: Записать данные
              FilledButton(
                onPressed: (_submitting || _openingWeb) ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Записать данные',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
              const SizedBox(height: 10),

              // Кнопка: Заполнить на сайте (с авторизованной ссылкой)
              OutlinedButton.icon(
                onPressed: (_submitting || _openingWeb) ? null : _openOnWeb,
                icon: _openingWeb
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.open_in_browser, size: 20),
                label: const Text('Заполнить на сайте stat.interra.ru'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: context.p.line),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
