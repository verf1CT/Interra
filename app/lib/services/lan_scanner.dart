import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// тип устройства в сети (грубо угадывается по открытым портам)
enum DeviceKind { thisPhone, router, apple, windows, printer, generic }

class LanDevice {
  final String ip;
  final DeviceKind kind;
  final List<int> openPorts;
  const LanDevice(this.ip, this.kind, this.openPorts);

  int get lastOctet => int.tryParse(ip.split('.').last) ?? 0;
}

/// результат сканирования локальной сети
typedef ScanResult = ({List<LanDevice> devices, String? subnet, bool noWifi});

/// сканер устройств в локальной сети (кто подключён к твоему Wi-Fi).
///
/// работает без плагинов: берём свой IPv4 из сетевых интерфейсов, определяем
/// подсеть /24 и пробуем TCP-подключение к каждому хосту на нескольких портах.
/// хост считаем живым, если порт открыт ИЛИ соединение отклонено (значит хост
/// на связи, просто порт закрыт). на iOS первый заход просит доступ к локальной
/// сети - без него сканирование ничего не найдёт
class LanScanner {
  // компактный набор портов: роутер/веб (80,443,7547), ssh (22), windows (445),
  // apple (62078), принтер (9100), альтернативный веб (8080)
  static const _ports = [80, 443, 22, 445, 62078, 9100, 7547, 8080];
  static const _connectTimeout = Duration(milliseconds: 500);
  static const _batch = 20; // хостов за раз (портов на хост - _ports.length)

  static bool _isPrivate(String ip) {
    final p = ip.split('.');
    if (p.length != 4) return false;
    final a = int.tryParse(p[0]) ?? 0, b = int.tryParse(p[1]) ?? 0;
    return a == 192 && b == 168 || a == 10 || (a == 172 && b >= 16 && b <= 31);
  }

  static bool _isWifiName(String name) {
    final n = name.toLowerCase();
    return n.startsWith('en') || n.startsWith('wlan') || n.contains('wl');
  }

  static bool _isCellularName(String name) {
    final n = name.toLowerCase();
    return n.startsWith('pdp_ip') || n.startsWith('rmnet') || n.contains('pdp');
  }

  /// (свой ip, база /24) или null, если Wi-Fi-подсеть не найдена
  static Future<(String, String)?> _subnet() async {
    try {
      final ifaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      String? wifi;
      String? fallback;
      for (final ni in ifaces) {
        for (final a in ni.addresses) {
          if (!_isPrivate(a.address)) continue;
          if (_isCellularName(ni.name)) continue; // мобильную сеть не сканируем
          if (_isWifiName(ni.name)) {
            wifi ??= a.address;
          } else {
            fallback ??= a.address;
          }
        }
      }
      final ip = wifi ?? fallback;
      if (ip == null) return null;
      final parts = ip.split('.');
      return (ip, '${parts[0]}.${parts[1]}.${parts[2]}');
    } catch (e) {
      debugPrint('LanScanner._subnet: $e');
      return null;
    }
  }

  /// возвращает открытые порты хоста; хост «живой», если список непуст ИЛИ был
  /// отказ в соединении (второе возвращаем отдельным флагом)
  static Future<(List<int> open, bool refused)> _probeHost(String ip) async {
    final open = <int>[];
    var refused = false;
    await Future.wait(_ports.map((port) async {
      try {
        final s = await Socket.connect(ip, port, timeout: _connectTimeout);
        s.destroy();
        open.add(port);
      } on SocketException catch (e) {
        final code = e.osError?.errorCode;
        // ECONNREFUSED: 61 (mac/iOS), 111 (linux/android), 10061 (win)
        if (code == 61 || code == 111 || code == 10061) refused = true;
      } catch (_) {}
    }));
    open.sort();
    return (open, refused);
  }

  static DeviceKind _classify(
      String ip, List<int> open, String ownIp, String gateway) {
    if (ip == ownIp) return DeviceKind.thisPhone;
    if (ip == gateway) return DeviceKind.router;
    if (open.contains(62078)) return DeviceKind.apple;
    if (open.contains(445) || open.contains(139)) return DeviceKind.windows;
    if (open.contains(9100)) return DeviceKind.printer;
    if (open.contains(7547) && (open.contains(80) || open.contains(443))) {
      return DeviceKind.router;
    }
    return DeviceKind.generic;
  }

  /// сканирует подсеть. [onProgress] — доля 0..1
  static Future<ScanResult> scan({void Function(double)? onProgress}) async {
    final sub = await _subnet();
    if (sub == null) {
      return (devices: <LanDevice>[], subnet: null, noWifi: true);
    }
    final (ownIp, base) = sub;
    final gateway = '$base.1';
    final found = <LanDevice>[];
    var done = 0;

    for (var start = 1; start <= 254; start += _batch) {
      final hosts = [
        for (var h = start; h < start + _batch && h <= 254; h++) '$base.$h'
      ];
      final results = await Future.wait(hosts.map((ip) async {
        final (open, refused) = await _probeHost(ip);
        return (ip, open, refused);
      }));
      for (final (ip, open, refused) in results) {
        if (open.isNotEmpty || refused || ip == ownIp) {
          found.add(LanDevice(ip, _classify(ip, open, ownIp, gateway), open));
        }
      }
      done += hosts.length;
      onProgress?.call(done / 254);
    }

    // свой телефон мог не ответить на собственные подключения - добавим явно
    if (!found.any((d) => d.ip == ownIp)) {
      found.add(LanDevice(ownIp, DeviceKind.thisPhone, const []));
    }
    found.sort((a, b) => a.lastOctet.compareTo(b.lastOctet));
    return (devices: found, subnet: '$base.0/24', noWifi: false);
  }
}
