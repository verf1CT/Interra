import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

class PaymentModal extends StatefulWidget {
  final String account;
  final String? recommendedAmount;

  const PaymentModal({
    super.key,
    required this.account,
    this.recommendedAmount,
  });

  static Future<void> show(
    BuildContext context, {
    required String account,
    String? recommendedAmount,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PaymentModal(
        account: account,
        recommendedAmount: recommendedAmount,
      ),
    );
  }

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> {
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    if (widget.account.isNotEmpty && widget.account != '—') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Clipboard.setData(ClipboardData(text: widget.account));
        if (mounted) {
          setState(() => _copied = true);
        }
      });
    }
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
    if (widget.account.isEmpty || widget.account == '—') return;
    Clipboard.setData(ClipboardData(text: widget.account));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Лицевой счёт ${widget.account} скопирован'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayAccount =
        (widget.account.isNotEmpty && widget.account != '—') ? widget.account : '—';
    final cardPayUrl = (widget.account.isNotEmpty && widget.account != '—')
        ? 'https://interra.ru/sberbank/?epay=${widget.account}'
        : 'https://interra.ru/sberbank/';

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      decoration: BoxDecoration(
        color: context.p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
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
                        Row(
                          children: [
                            Text(
                              displayAccount,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                color: context.p.ink,
                              ),
                            ),
                            if (_copied) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Скопирован',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ],
                          ],
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

            if (widget.recommendedAmount != null &&
                widget.recommendedAmount!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFEF4444),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Рекомендуемая сумма для включения услуг: ${widget.recommendedAmount}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

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
              child: Text(
                'Банковская карта, SberPay, T-Pay, СБП',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.p.ink,
                ),
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
          ],
        ),
      ),
    );
  }
}
