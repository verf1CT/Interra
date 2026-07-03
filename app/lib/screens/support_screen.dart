import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../theme.dart';
import '../services/analytics.dart';
import 'diagnostics_screen.dart';
import 'speedtest_screen.dart';
import 'lan_devices_screen.dart';

/// экран «Поддержка»: связь с провайдером (звонок, Telegram, ВКонтакте, помощь
/// на сайте) и версия приложения. контакты - из [AppConfig]
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  Future<void> _open(Uri uri, String channel) async {
    Analytics.supportOpened(channel);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Поддержка: не удалось открыть $uri: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поддержка')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _hero(),
          const SizedBox(height: 18),
          _sectionTitle('Связаться'),
          _group([
            _tile(
              icon: Icons.phone_in_talk_rounded,
              color: AppColors.ok,
              title: 'Позвонить в поддержку',
              subtitle: AppConfig.supportPhoneHuman,
              onTap: () => _open(
                  Uri(scheme: 'tel', path: AppConfig.supportPhone), 'phone'),
            ),
          ]),
          const SizedBox(height: 18),
          _sectionTitle('Мы в соцсетях'),
          _group([
            _tile(
              icon: Icons.campaign_rounded,
              color: const Color(0xFF2AABEE),
              title: 'Telegram-канал',
              subtitle: 'Новости и статус сети',
              onTap: () => _open(
                  Uri.parse('https://t.me/${AppConfig.supportTelegram}'),
                  'telegram'),
            ),
            _divider(),
            _tile(
              icon: Icons.groups_rounded,
              color: const Color(0xFF0077FF),
              title: 'Сообщество ВКонтакте',
              subtitle: 'Новости и обращения',
              onTap: () =>
                  _open(Uri.parse(AppConfig.supportVkUrl), 'vk'),
            ),
          ]),
          const SizedBox(height: 18),
          _sectionTitle('Самостоятельно'),
          _group([
            Builder(
              builder: (context) => _tile(
                icon: Icons.network_check_rounded,
                color: AppColors.accent,
                title: 'Диагностика сети',
                subtitle: 'Проверить, где проблема с интернетом',
                onTap: () {
                  Analytics.supportOpened('diagnostics');
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const DiagnosticsScreen(),
                    settings: const RouteSettings(name: 'diagnostics'),
                  ));
                },
              ),
            ),
            _divider(),
            Builder(
              builder: (context) => _tile(
                icon: Icons.speed_rounded,
                color: AppColors.brand,
                title: 'Проверка скорости',
                subtitle: 'Замерить скорость интернета',
                onTap: () {
                  Analytics.supportOpened('speedtest');
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SpeedTestScreen(),
                    settings: const RouteSettings(name: 'speedtest'),
                  ));
                },
              ),
            ),
            _divider(),
            Builder(
              builder: (context) => _tile(
                icon: Icons.devices_rounded,
                color: AppColors.brand,
                title: 'Устройства в сети',
                subtitle: 'Кто подключён к твоему Wi-Fi',
                onTap: () {
                  Analytics.supportOpened('lan');
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const LanDevicesScreen(),
                    settings: const RouteSettings(name: 'lan_devices'),
                  ));
                },
              ),
            ),
            _divider(),
            _tile(
              icon: Icons.help_outline_rounded,
              color: AppColors.brand,
              title: 'Помощь на сайте',
              subtitle: 'Ответы на частые вопросы',
              onTap: () =>
                  _open(Uri.parse(AppConfig.supportHelpUrl), 'help'),
            ),
          ]),
          const SizedBox(height: 24),
          Center(
            child: Text('ЛК Интерра · v${AppConfig.appVersion}',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// шапка: чистая карточка со значком поддержки и подсказкой (без градиента)
  Widget _hero() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.support_agent_rounded,
                  color: AppColors.brand, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Мы на связи',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'Поможем с подключением, оплатой и настройкой интернета',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                        height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
        onTap: onTap,
      );

  Widget _group(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(children: children),
      );

  Widget _divider() => const Divider(
      height: 1, thickness: 1, indent: 68, color: AppColors.line);

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
            letterSpacing: 0.5,
          ),
        ),
      );
}
