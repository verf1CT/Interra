import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/balance_store.dart';
import '../services/site_pay.dart';
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
  Timer? _copiedTimer;

  /// поле суммы нужно только для оплаты картой: раскрываем его по кнопке
  bool _cardOpen = false;
  final _amountFocus = FocusNode();
  late final _amount = TextEditingController(
    text: RegExp(r'\d+').firstMatch(widget.recommendedAmount ?? '')?.group(0) ?? '',
  );
  bool _paying = false;
  String? _payError;

  bool get _hasAccount => widget.account.isNotEmpty && widget.account != '-';
  int? get _sum {
    final v = int.tryParse(_amount.text.trim());
    return v != null && v > 0 ? v : null;
  }

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() => _payError = null));
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _amountFocus.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _copyAccount() {
    if (!_hasAccount || !mounted) return;
    Clipboard.setData(ClipboardData(text: widget.account));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _toggleCard() {
    HapticFeedback.selectionClick();
    setState(() => _cardOpen = !_cardOpen);
    if (_cardOpen) {
      // ждём, пока поле появится, иначе фокус некуда ставить
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _cardOpen) _amountFocus.requestFocus();
      });
    } else {
      _amountFocus.unfocus();
    }
  }

  /// сразу на страницу банка: ссылку отдаёт API сайта. сайт не ответил -
  /// открываем его форму оплаты
  Future<void> _payByCard() async {
    final amount = _sum;
    if (amount == null) {
      setState(() => _payError = 'Введите сумму');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_hasAccount) {
      await _launch(SitePay.fallbackUrl(''), close: true);
      return;
    }
    setState(() {
      _paying = true;
      _payError = null;
    });
    final link = await SitePay.request(widget.account, amount);
    if (!mounted) return;
    setState(() => _paying = false);
    if (link.error != null) {
      setState(() => _payError = link.error);
    } else {
      await _launch(link.url ?? SitePay.fallbackUrl(widget.account), close: true);
    }
  }

  Future<void> _launch(String urlString, {bool close = false}) async {
    try {
      final ok = await launchUrl(Uri.parse(urlString), mode: LaunchMode.externalApplication);
      // страница оплаты открылась - шторка больше не нужна
      if (ok && close && mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Не удалось открыть ссылку $urlString: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Пополнение счёта',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.ink)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _accountCard(),
                if (widget.recommendedAmount != null && widget.recommendedAmount!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _recommended(),
                ],
                const SizedBox(height: 16),
                _cardPayment(),
                const SizedBox(height: 12),
                _methodButton(
                  title: 'Сбербанк Онл@йн',
                  subtitle: '(обязательно выбирайте регион: Свердловская область)',
                  // в Сбербанке счёт вводят руками, поэтому копируем его по нажатию
                  onTap: () {
                    _copyAccount();
                    _launch('https://online.sberbank.ru/');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountCard() {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ваш лицевой счёт для оплаты в платёжных системах',
                    style: TextStyle(fontSize: 12, color: p.inkMute, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(_hasAccount ? widget.account : '-',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.ink)),
                    const SizedBox(width: 8),
                    // пилюля выезжает слева и сама гаснет через пару секунд
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(-0.25, 0), end: Offset.zero).animate(a),
                          child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: child),
                        ),
                      ),
                      child: _copied
                          ? Container(
                              key: const ValueKey('copied'),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.ok.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Скопирован',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ok)),
                            )
                          : const SizedBox.shrink(key: ValueKey('idle')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Скопировать счёт',
            onPressed: _copyAccount,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: _copied
                  ? const Icon(Icons.check_rounded, key: ValueKey('check'), size: 20, color: AppColors.ok)
                  : const Icon(Icons.copy_rounded, key: ValueKey('copy'), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommended() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Рекомендуемая сумма для включения услуг: ${widget.recommendedAmount}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  /// кнопка способа оплаты, которая раскрывается в поле суммы и кнопку «Оплатить»
  Widget _cardPayment() {
    final p = context.p;
    final sum = _sum;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardOpen ? AppColors.brand.withValues(alpha: 0.5) : p.line),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _paying ? null : _toggleCard,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Text('Банковская карта, SberPay, T-Pay, СБП',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.ink)),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_cardOpen
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _amount,
                            focusNode: _amountFocus,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) => _payByCard(),
                            onTapOutside: (_) => _amountFocus.unfocus(),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.ink),
                            decoration: InputDecoration(
                              labelText: 'Сумма, ₽',
                              errorText: _payError,
                              errorMaxLines: 3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _paying || sum == null ? null : _payByCard,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.brand,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: _paying
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(
                                      sum == null
                                          ? 'Введите сумму'
                                          : 'Оплатить ${BalanceStore.format(sum.toDouble())}',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodButton({required String title, required String subtitle, required VoidCallback onTap}) {
    final p = context.p;
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: p.card,
        foregroundColor: p.ink,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.line),
        ),
      ),
      child: Column(
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.ink)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: p.inkMute, fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}
