import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

/// тип устройства в сети (грубо угадывается по открытым портам)
enum DeviceKind { thisPhone, router, apple, windows, printer, generic }

class LanDevice {
  final String ip;
  final DeviceKind kind;
  final List<int> openPorts;

  /// человекочитаемое имя из mDNS (если удалось узнать), например «iPhone Миши»
  final String? name;

  const LanDevice(this.ip, this.kind, this.openPorts, {this.name});

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
  // компактный набор портов: веб (80,443), ssh (22), windows (445),
  // apple (62078), принтер (9100)
  static const _ports = [80, 443, 22, 445, 62078, 9100];
  static const _connectTimeout = Duration(milliseconds: 500);

  // ограничитель одновременных сокетов: без него batch×ports упирается в лимит
  // файловых дескрипторов (на iOS ~256) и часть подключений тихо срывается,
  // теряя устройства
  static final _Semaphore _sem = _Semaphore(128);

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
      await _sem.acquire();
      try {
        final s = await Socket.connect(ip, port, timeout: _connectTimeout);
        s.destroy();
        open.add(port);
      } on SocketException catch (e) {
        final code = e.osError?.errorCode;
        // ECONNREFUSED: 61 (mac/iOS), 111 (linux/android), 10061 (win)
        if (code == 61 || code == 111 || code == 10061) refused = true;
      } catch (_) {
      } finally {
        _sem.release();
      }
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
    return DeviceKind.generic;
  }

  /// сканирует подсеть. [onProgress] — доля 0..1. параллелизм сокетов ограничен
  /// семафором, поэтому запускаем сразу все хосты
  static Future<ScanResult> scan({void Function(double)? onProgress}) async {
    final sub = await _subnet();
    if (sub == null) {
      return (devices: <LanDevice>[], subnet: null, noWifi: true);
    }
    final (ownIp, base) = sub;
    final gateway = '$base.1';
    final found = <LanDevice>[];
    var done = 0;

    // имена по mDNS резолвим параллельно с портовым сканом, чтобы не удлинять
    final namesFuture = _resolveNames();

    await Future.wait([
      for (var h = 1; h <= 254; h++)
        () async {
          final ip = '$base.$h';
          final (open, refused) = await _probeHost(ip);
          if (open.isNotEmpty || refused || ip == ownIp) {
            found.add(LanDevice(ip, _classify(ip, open, ownIp, gateway), open));
          }
          done++;
          onProgress?.call(done / 254);
        }()
    ]);

    // свой телефон мог не ответить на собственные подключения - добавим явно
    if (!found.any((d) => d.ip == ownIp)) {
      found.add(LanDevice(ownIp, DeviceKind.thisPhone, const []));
    }

    // подмешиваем имена из mDNS
    final names = await namesFuture;
    final named = [
      for (final d in found)
        LanDevice(d.ip, d.kind, d.openPorts, name: names[d.ip])
    ]..sort((a, b) => a.lastOctet.compareTo(b.lastOctet));
    return (devices: named, subnet: '$base.0/24', noWifi: false);
  }

  /// имена устройств через mDNS/Bonjour: ip -> дружелюбное имя. best-effort,
  /// на iOS требует NSLocalNetworkUsageDescription и NSBonjourServices в plist
  static Future<Map<String, String>> _resolveNames() async {
    final map = <String, String>{};
    final client = MDnsClient();
    try {
      await client.start();
      const services = [
        '_companion-link._tcp.local', // iPhone/iPad/Mac
        '_airplay._tcp.local', // Apple TV, колонки
        '_raop._tcp.local', // AirPlay-аудио
        '_googlecast._tcp.local', // Chromecast, телевизоры
        '_smb._tcp.local', // компьютеры/NAS
        '_ipp._tcp.local', // принтеры
        '_printer._tcp.local',
        '_ssh._tcp.local',
        '_http._tcp.local', // роутеры/NAS
        '_workstation._tcp.local', // linux/windows-хосты
      ];
      await Future.wait(services.map((s) => _browse(client, s, map)))
          .timeout(const Duration(seconds: 5), onTimeout: () => const []);
    } catch (e) {
      debugPrint('mDNS: $e');
    } finally {
      client.stop();
    }
    return map;
  }

  static Future<void> _browse(
      MDnsClient client, String service, Map<String, String> out) async {
    try {
      await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(service),
          timeout: const Duration(seconds: 4))) {
        final friendly = _instanceName(ptr.domainName);
        if (friendly.isEmpty) continue;
        await for (final srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
            timeout: const Duration(seconds: 3))) {
          await for (final a in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
              timeout: const Duration(seconds: 3))) {
            out.putIfAbsent(a.address.address, () => friendly);
          }
        }
      }
    } catch (_) {/* один сервис не ответил - не критично */}
  }

  /// «Гостиная._googlecast._tcp.local» -> «Гостиная»
  static String _instanceName(String domain) {
    final i = domain.indexOf('._');
    final label = i > 0 ? domain.substring(0, i) : domain;
    // mDNS экранирует пробелы как «\ » и точки как «\.»
    return label.replaceAll(r'\ ', ' ').replaceAll(r'\.', '.').trim();
  }
}

/// простой семафор: ограничивает число одновременных операций
class _Semaphore {
  int _permits;
  final _waiters = <Completer<void>>[];
  _Semaphore(this._permits);

  Future<void> acquire() {
    if (_permits > 0) {
      _permits--;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _permits++;
    }
  }
}
