import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Главная карточка Premium TV
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F70B7), Color(0xFF1990E6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F70B7).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.tv_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Интерра ТВ',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Премиальное интерактивное ТВ',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Более 150 телеканалов в цифровом и Full HD качестве. Архив передач до 7 дней, пауза, перемотка и просмотр на смартфонах, планшетах и Smart TV.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _openUrl('https://online.interra.ru/'),
                      icon: const Icon(Icons.play_circle_fill, size: 18),
                      label: const Text('Смотреть онлайн'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F70B7),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text(
          'Пакеты каналов',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: context.p.ink,
          ),
        ),
        const SizedBox(height: 12),

        _buildCategoryCard(
          context,
          icon: Icons.public,
          title: 'Общероссийские и информационные',
          count: '24 канала',
          channels: 'Первый HD, Россия 1 HD, Матч ТВ HD, НТВ HD, Пятый канал, Россия К, Россия 24, ОТР, ТВ Центр, РЕН ТВ, Спас, СТС, Домашний, ТВ-3, Пятница!, Звезда, МИР, ТНТ, Муз-ТВ',
        ),
        const SizedBox(height: 12),

        _buildCategoryCard(
          context,
          icon: Icons.movie_filter_rounded,
          title: 'Кино и сериалы',
          count: '38 каналов',
          channels: 'Кинокомедия HD, Киносемья HD, Киномикс HD, Родное кино, FOX HD, TV1000 HD, TV1000 Action, Киносерия, Кино ТВ HD, Русский Роман HD, Paramount Channel',
        ),
        const SizedBox(height: 12),

        _buildCategoryCard(
          context,
          icon: Icons.sports_soccer_rounded,
          title: 'Спорт',
          count: '16 каналов',
          channels: 'Матч Премьер HD, Матч! Футбол 1/2/3 HD, Матч! Боец, КХЛ HD, Старт HD, Extreme Sports, Мир Баскетбола, Моторспорт ТВ',
        ),
        const SizedBox(height: 12),

        _buildCategoryCard(
          context,
          icon: Icons.explore_rounded,
          title: 'Познавательные и путешествия',
          count: '28 каналов',
          channels: 'Discovery HD, National Geographic HD, Моя Планета, Наука 2.0, Живая Планета, Animal Planet HD, Travel+Adventure HD, История, RTG HD',
        ),
        const SizedBox(height: 12),

        _buildCategoryCard(
          context,
          icon: Icons.child_care_rounded,
          title: 'Детские',
          count: '14 каналов',
          channels: 'Мульт HD, Карусель, СТС Kids HD, Мультиландия, О!, Nickelodeon, Disney, Детский Мир, В гостях у сказки',
        ),
        const SizedBox(height: 24),

        // Помощь по настройке
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.p.line),
          ),
          child: Row(
            children: [
              Icon(Icons.help_outline_rounded, color: context.p.inkMute, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Как смотреть на Smart TV?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.p.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Установите приложение «Интерра ТВ» на телевизор Samsung, LG или Android TV.',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.p.inkMute,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openUrl('https://interra.ru/help/'),
                child: const Text('Инструкция'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String count,
    required String channels,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.p.ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  count,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            channels,
            style: TextStyle(
              fontSize: 13,
              color: context.p.inkMute,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
