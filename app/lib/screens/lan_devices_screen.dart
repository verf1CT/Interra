import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/analytics.dart';
import '../services/lan_scanner.dart';

/// экран «устройства в сети»: кто подключён к твоему Wi-Fi
class LanDevicesScreen extends StatefulWidget {
  const LanDevicesScreen({super.key});

  @override
  State<LanDevicesScreen> createState() => _LanDevicesScreenState();
}

class _LanDevicesScreenState extends State<LanDevicesScreen> {
  bool _scanning = false;
  double _progress = 0;
  ScanResult _result = (devices: [], subnet: null, noWifi: false);

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _progress = 0;
    });
    final r = await LanScanner.scan(
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    Analytics.log('lan_scan', {'devices': r.devices.length});
    if (!mounted) return;
    setState(() {
      _result = r;
      _scanning = false;
    });
  }

  static ({IconData icon, String label, Color color}) _meta(DeviceKind k) =>
      switch (k) {
        DeviceKind.thisPhone => (
            icon: Icons.smartphone_rounded,
            label: 'Этот телефон',
            color: AppColors.brand
          ),
        DeviceKind.router => (
            icon: Icons.router_rounded,
            label: 'Роутер',
            color: AppColors.accent
          ),
        DeviceKind.apple => (
            icon: Icons.laptop_mac_rounded,
            label: 'Устройство Apple',
            color: AppColors.brand
          ),
        DeviceKind.windows => (
            icon: Icons.computer_rounded,
            label: 'Компьютер Windows',
            color: AppColors.brand
          ),
        DeviceKind.printer => (
            icon: Icons.print_rounded,
            label: 'Принтер',
            color: AppColors.inkMute
          ),
        DeviceKind.generic => (
            icon: Icons.devices_other_rounded,
            label: 'Устройство',
            color: AppColors.inkMute
          ),
      };

  @override
  Widget build(BuildContext context) {
    final d = _result.devices;
    return Scaffold(
      appBar: AppBar(title: const Text('Устройства в сети')),
      body: _result.noWifi && !_scanning
          ? _noWifi()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(d.length),
                const SizedBox(height: 16),
                if (d.isEmpty && _scanning)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _list(d),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: const Icon(Icons.refresh),
                  label: Text(_scanning ? 'Сканируем…' : 'Сканировать заново'),
                ),
                const SizedBox(height: 12),
                Text(
                  'показаны устройства, подключённые к тому же Wi-Fi. некоторые '
                  'могут не отвечать на опрос - это нормально. если увидели '
                  'чужого - смените пароль Wi-Fi на роутере',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.inkFaint, height: 1.4),
                ),
              ],
            ),
    );
  }

  Widget _header(int count) => Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
        decoration: cardBox(radius: 14),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_rounded,
                  color: AppColors.brand, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              _scanning ? 'ищем устройства…' : '$count в сети',
              style: const TextStyle(
                  color: AppColors.ink, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            if (_result.subnet != null)
              Text(_result.subnet!,
                  style: const TextStyle(color: AppColors.inkFaint, fontSize: 12)),
            if (_scanning) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  minHeight: 5,
                  color: AppColors.brand,
                  backgroundColor: AppColors.surfaceAlt,
                ),
              ),
            ],
          ],
        ),
      );

  Widget _list(List<LanDevice> devices) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: cardBox(),
        child: Column(
          children: [
            for (var i = 0; i < devices.length; i++) ...[
              if (i > 0)
                const Divider(
                    height: 1, thickness: 1, indent: 64, color: AppColors.line),
              _tile(devices[i]),
            ],
          ],
        ),
      );

  Widget _tile(LanDevice d) {
    final m = _meta(d.kind);
    final special =
        d.kind == DeviceKind.thisPhone || d.kind == DeviceKind.router;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: m.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(m.icon, color: m.color, size: 22),
      ),
      title: Text(m.label,
          style: TextStyle(
              fontWeight: special ? FontWeight.w700 : FontWeight.w600,
              fontSize: 15)),
      subtitle: Text(d.ip),
      trailing: special
          ? Text(d.kind == DeviceKind.thisPhone ? 'вы' : 'шлюз',
              style: TextStyle(
                  color: m.color, fontSize: 12, fontWeight: FontWeight.w600))
          : null,
    );
  }

  Widget _noWifi() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.inkFaint),
              const SizedBox(height: 16),
              const Text('Нужен Wi-Fi',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'подключитесь к домашнему Wi-Fi, чтобы увидеть устройства сети. '
                'по мобильному интернету это не работает',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkMute, height: 1.4),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.refresh),
                label: const Text('Проверить снова'),
              ),
            ],
          ),
        ),
      );
}
