import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../widgets/design_system.dart';
import '../widgets/motion_kit.dart';

/// вкладка «ТВ»: описание сервиса, пакеты каналов (раскрываются по нажатию),
/// ссылка на просмотр онлайн и инструкция для Smart TV.
/// состав пакетов и числа - справочный текст, в биллинге их нет
class PremiumTvScreen extends StatelessWidget {
  const PremiumTvScreen({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Не удалось открыть $url: $e');
    }
  }

  static const _packages = [
    _Package(
      icon: Icons.public_rounded,
      title: 'Общероссийские и информационные',
      count: '24 канала',
      channels:
          'Первый HD, Россия 1 HD, Матч ТВ HD, НТВ HD, Пятый канал, Россия К, Россия 24, ОТР, ТВ Центр, РЕН ТВ, Спас, СТС, Домашний, ТВ-3, Пятница!, Звезда, МИР, ТНТ, Муз-ТВ',
    ),
    _Package(
      icon: Icons.movie_filter_rounded,
      title: 'Кино и сериалы',
      count: '38 каналов',
      channels:
          'Кинокомедия HD, Киносемья HD, Киномикс HD, Родное кино, FOX HD, TV1000 HD, TV1000 Action, Киносерия, Кино ТВ HD, Русский Роман HD, Paramount Channel',
    ),
    _Package(
      icon: Icons.sports_soccer_rounded,
      title: 'Спорт',
      count: '16 каналов',
      channels:
          'Матч Премьер HD, Матч! Футбол 1/2/3 HD, Матч! Боец, КХЛ HD, Старт HD, Extreme Sports, Мир Баскетбола, Моторспорт ТВ',
    ),
    _Package(
      icon: Icons.explore_rounded,
      title: 'Познавательные и путешествия',
      count: '28 каналов',
      channels:
          'Discovery HD, National Geographic HD, Моя Планета, Наука 2.0, Живая Планета, Animal Planet HD, Travel+Adventure HD, История, RTG HD',
    ),
    _Package(
      icon: Icons.child_care_rounded,
      title: 'Детские',
      count: '14 каналов',
      channels:
          'Мульт HD, Карусель, СТС Kids HD, Мультиландия, О!, Nickelodeon, Disney, Детский Мир, В гостях у сказки',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        StaggerIn(index: 0, child: _hero(context)),
        const SizedBox(height: 22),
        const PillSectionHeader('Пакеты каналов'),
        for (var i = 0; i < _packages.length; i++) ...[
          StaggerIn(
            index: i + 1,
            child: _PackageCard(package: _packages[i], initiallyOpen: i == 0),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        StaggerIn(
          index: _packages.length + 1,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            decoration: cardBox(context, radius: 22),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.connected_tv_rounded,
                      size: 22,
                      color: dark ? AppColors.brand : AppColors.brandInk),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Как смотреть на Smart TV',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: p.ink)),
                      const SizedBox(height: 2),
                      Text(
                        'Приложение «Интерра ТВ» для Samsung, LG и Android TV',
                        style: TextStyle(
                            fontSize: 12.5, color: p.inkMute, height: 1.3),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: () => _openUrl('https://interra.ru/help/'),
                  child: const Text('Инструкция'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _hero(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const radius = 26.0;

    Widget fact(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: brandGradient(dark),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: AppColors.brandInk.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.live_tv_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Интерра ТВ',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Премиальное интерактивное ТВ',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              fact('Более 150 каналов'),
              fact('Архив до 7 дней'),
              fact('Пауза, перемотка'),
              fact('Смартфон и Smart TV'),
            ],
          ),
          const SizedBox(height: 18),
          Pressable(
            onTap: () => _openUrl('https://online.interra.ru/'),
            semanticLabel: 'Смотреть онлайн',
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded,
                      size: 22, color: AppColors.brandInk),
                  SizedBox(width: 6),
                  Text(
                    'Смотреть онлайн',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Package {
  final IconData icon;
  final String title;
  final String count;
  final String channels;

  const _Package({
    required this.icon,
    required this.title,
    required this.count,
    required this.channels,
  });
}

/// пакет каналов: свёрнутый показывает одну строку-превью, раскрытый - чипы
class _PackageCard extends StatefulWidget {
  final _Package package;
  final bool initiallyOpen;

  const _PackageCard({required this.package, this.initiallyOpen = false});

  @override
  State<_PackageCard> createState() => _PackageCardState();
}

class _PackageCardState extends State<_PackageCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pkg = widget.package;
    final names = pkg.channels.split(', ');

    return Container(
      decoration: cardBox(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pressable(
            scale: 0.985,
            semanticLabel: '${pkg.title}, ${pkg.count}',
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: p.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(pkg.icon,
                        size: 22,
                        color: dark ? AppColors.brand : AppColors.brandInk),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pkg.title,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                                height: 1.25)),
                        const SizedBox(height: 2),
                        Text(pkg.count,
                            style: TextStyle(fontSize: 12.5, color: p.inkMute)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 420),
                    curve: SpringCurve.bouncy,
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 26, color: p.inkFaint),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final n in names)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: p.surfaceAlt,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(n,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: p.ink)),
                          ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(
                        pkg.channels,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.inkFaint),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
