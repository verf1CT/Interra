import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../theme.dart';
import '../services/analytics.dart';
import '../services/app_info.dart';
import '../widgets/ui_kit.dart';
import 'diagnostics_screen.dart';
import 'lan_devices_screen.dart';

/// экран «Поддержка»: связь с провайдером (звонок, ВКонтакте, помощь
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
          _hero(context),
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
            child: Text('ЛК Интерра · v${AppInfo.version}',
                style: TextStyle(color: context.p.inkFaint, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// шапка: чистая карточка со значком поддержки и подсказкой (без градиента)
  Widget _hero(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: cardBox(context),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
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
                        color: context.p.inkMute,
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
        leading: IconChip(icon, color),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  Widget _group(List<Widget> children) =>
      AppCard(clip: true, child: Column(children: children));

  Widget _divider() => const Divider(
      height: 1, thickness: 1, indent: 68);

  Widget _sectionTitle(String text) => AppSectionTitle(text);
}
