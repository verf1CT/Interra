import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../services/auth_store.dart';
import '../services/cabinet_parser.dart';

class PaymentModal extends StatefulWidget {
  final String account;

  const PaymentModal({super.key, required this.account});

  static Future<void> show(BuildContext context, {required String account}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentModal(account: account),
    );
  }

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> {
  final TextEditingController _certController = TextEditingController();
  bool _activating = false;
  String? _certMessage;
  bool _certSuccess = false;

  @override
  void dispose() {
    _certController.dispose();
    super.dispose();
  }

  Future<void> _launch(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Не удалось открыть ссылку $urlString: $e');
    }
  }

  void _copyAccount() {
    if (widget.account.isEmpty) return;
    Clipboard.setData(ClipboardData(text: widget.account));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Лицевой счёт ${widget.account} скопирован'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _activateCertificate() async {
    final code = _certController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _activating = true;
      _certMessage = null;
    });

    try {
      final token = await AuthStore().appToken;
      if (token == null) throw Exception('auth_expired');

      final ok = await CabinetParser.activateCertificate(token, code);
      if (mounted) {
        setState(() {
          _activating = false;
          _certSuccess = ok;
          _certMessage = ok
              ? 'Сертификат успешно активирован!'
              : 'Не удалось активировать. Проверьте правильность кода.';
        });
        if (ok) {
          _certController.clear();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _activating = false;
          _certSuccess = false;
          _certMessage = 'Ошибка отправки. Попробуйте позже.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayAccount = widget.account.isNotEmpty ? widget.account : '—';
    final cardPayUrl = widget.account.isNotEmpty
        ? 'https://interra.ru/sberbank/?epay=${widget.account}'
        : 'https://interra.ru/sberbank/';

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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Пополнение счёта',
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
            const SizedBox(height: 16),

            // Карточка с лицевым счётом
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: context.p.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.p.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ваш лицевой счет для оплаты в платежных системах',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.p.inkMute,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          displayAccount,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: context.p.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    tooltip: 'Скопировать счёт',
                    onPressed: _copyAccount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Кнопка 1: Банковская карта, SberPay, T-Pay, СБП
            ElevatedButton(
              onPressed: () => _launch(cardPayUrl),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.p.card,
                foregroundColor: context.p.ink,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: context.p.line),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Банковская карта, SberPay, T-Pay, СБП',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.p.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Кнопка 2: Сбербанк Онлайн
            ElevatedButton(
              onPressed: () => _launch('https://online.sberbank.ru/'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.p.card,
                foregroundColor: context.p.ink,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: context.p.line),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Сбербанк Онл@йн',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.p.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(обязательно выбирайте регион: Свердловская область)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.p.inkMute,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Секция: Сертификаты и карты оплаты
            Text(
              'Оплата сертификатом или картой',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.p.ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _certController,
                    decoration: InputDecoration(
                      hintText: 'Код карты или сертификата',
                      isDense: true,
                      filled: true,
                      fillColor: context.p.card,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.p.line),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _activating ? null : _activateCertificate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _activating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Активировать'),
                ),
              ],
            ),
            if (_certMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _certMessage!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _certSuccess ? AppColors.brand : AppColors.danger,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
