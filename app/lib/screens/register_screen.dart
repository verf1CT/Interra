import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../utils/phone.dart';
import '../services/auth_store.dart';
import '../services/billing_api.dart';
import '../services/push_service.dart';
import '../services/analytics.dart';
import 'webview_screen.dart';

/// Форматирует ввод телефона как `922 999-99-99` (без кода страны, до 10 цифр).
class _RuPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = formatRuPhoneTyping(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Регистрация приложения в биллинге по схеме `bbb`:
/// телефон → SMS-код → один раз получаем и храним токен приложения.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

enum _Step { phone, code }

class _RegisterScreenState extends State<RegisterScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();

  _Step _step = _Step.phone;
  bool _busy = false;
  String? _error;
  String? _appToken; // токен из первичной регистрации (для шага подтверждения)

  // Антиспам повторной отправки SMS: после успешного запроса кода блокируем
  // повторную отправку на 60 секунд и показываем обратный отсчёт.
  Timer? _resendTimer;
  int _resendLeft = 0;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendLeft = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendLeft--);
      if (_resendLeft <= 0) t.cancel();
    });
  }

  String get _normalizedPhone {
    return normalizeRuPhone(_phone.text);
  }

  /// Шаг телефона: первичная регистрация (один раз) + запрос SMS.
  Future<void> _submitPhone() async {
    final phone = _normalizedPhone;
    if (phone.length < 11) {
      setState(() => _error = 'Введите номер телефона полностью');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    // Переиспользуем токен, если первичная регистрация уже была (например,
    // приложение закрыли между шагами).
    var token = await AuthStore().appToken;
    if (token == null) {
      token = await BillingApi.registerPrimary();
      if (token == null) {
        setState(() {
          _busy = false;
          _error = 'Не удалось начать регистрацию. Попробуйте позже.';
        });
        return;
      }
      await AuthStore().saveAppToken(token);
    }
    _appToken = token;

    final r = await BillingApi.requestSms(phone, token);
    if (!mounted) return;
    if (r.isOk) {
      setState(() {
        _busy = false;
        _step = _Step.code;
      });
      _startResendCooldown();
    } else {
      // '0' — биллинг не знает наш токен (первичная регистрация потеряна).
      // Сбрасываем его, иначе каждая следующая попытка упрётся в тот же отказ.
      if (r.code == '0') {
        await AuthStore().clear();
        _appToken = null;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = r.networkError
            ? 'Нет связи с биллингом. Проверьте интернет.'
            : r.code == '1'
                ? 'Этот номер не привязан к лицевому счёту в Интерре.'
                : r.code == '0'
                    ? 'Сбой регистрации. Попробуйте ещё раз.'
                    : 'Не удалось отправить код. Попробуйте позже.';
      });
    }
  }

  /// Шаг кода: подтверждаем SMS-код, сохраняем телефон, входим.
  Future<void> _submitCode() async {
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    final token = _appToken;
    if (code.isEmpty || token == null) {
      setState(() => _error = 'Введите код из SMS');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final r = await BillingApi.confirmSms(code, token);
    if (!mounted) return;
    if (r.isOk) {
      await AuthStore().savePhone(_normalizedPhone);
      Analytics.setUser(_normalizedPhone);
      Analytics.loginCompleted();
      await PushService.registerCurrentToken();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WebViewScreen()),
      );
    } else {
      // '1' — первичная регистрация утеряна: токен мёртв, сбрасываем и
      // возвращаем на шаг телефона, чтобы регистрация началась заново.
      if (r.code == '1') {
        await AuthStore().clear();
        _appToken = null;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (r.code == '1') _step = _Step.phone;
        _error = r.networkError
            ? 'Нет связи с биллингом. Проверьте интернет.'
            : r.code == '0'
                ? 'Неверный код. Проверьте SMS и попробуйте снова.'
                : r.code == '1'
                    ? 'Регистрация устарела. Запросите код заново.'
                    : 'Не удалось подтвердить код. Попробуйте позже.';
      });
    }
  }

  /// Повторная отправка SMS тем же токеном (кнопка активна только после отсчёта).
  Future<void> _resendCode() async {
    final token = _appToken;
    if (token == null) return _backToPhone();
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await BillingApi.requestSms(_normalizedPhone, token);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = r.isOk ? null : 'Не удалось отправить код повторно.';
    });
    if (r.isOk) _startResendCooldown();
  }

  void _backToPhone() {
    _resendTimer?.cancel();
    setState(() {
      _step = _Step.phone;
      _error = null;
      _resendLeft = 0;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brand.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/splash_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Интерра',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C1F24),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Личный кабинет',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _step == _Step.phone ? _phoneForm() : _codeForm(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13.5),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    _step == _Step.phone
                        ? 'Укажите номер телефона, привязанный\nк вашему лицевому счёту Интерры'
                        : 'Мы отправили код подтверждения\nв SMS на $_normalizedPhone',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade500,
                        height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneForm() {
    return Column(
      children: [
        TextField(
          controller: _phone,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [_RuPhoneInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Телефон',
            hintText: '922 999-99-99',
            prefixIcon: Icon(Icons.phone_outlined),
            prefixText: '+7 ',
          ),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _busy ? null : _submitPhone,
          child: _busy ? _spinner() : const Text('Получить код'),
        ),
      ],
    );
  }

  Widget _codeForm() {
    return Column(
      children: [
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          autofocus: true,
          // iOS/Android подставят код из SMS прямо над клавиатурой.
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Код из SMS',
            prefixIcon: Icon(Icons.sms_outlined),
          ),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _busy ? null : _submitCode,
          child: _busy ? _spinner() : const Text('Подтвердить'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: (_busy || _resendLeft > 0) ? null : _resendCode,
          child: Text(
            _resendLeft > 0
                ? 'Отправить код повторно ($_resendLeft)'
                : 'Отправить код повторно',
            style: TextStyle(
                color: _resendLeft > 0
                    ? Colors.grey.shade400
                    : AppColors.brand),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _backToPhone,
          child: const Text('Изменить номер',
              style: TextStyle(color: Color(0xFF6B7280))),
        ),
      ],
    );
  }

  Widget _spinner() => const SizedBox(
        width: 22,
        height: 22,
        child:
            CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
}
