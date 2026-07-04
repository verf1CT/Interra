import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';

/// тип устройства в сети (по mDNS-сервису, иначе грубо по открытым портам)
enum DeviceKind { thisPhone, router, apple, tv, computer, printer, generic }

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

  /// по портам определяем ТОЛЬКО себя, роутер и принтер (9100 - однозначный
  /// признак). тип «Apple/компьютер/ТВ» по портам не выдумываем - это ненадёжно
  /// и раздражает; их даёт только mDNS. остальное - нейтральное «устройство»
  static DeviceKind _classifyByPorts(
      String ip, List<int> open, String ownIp, String gateway) {
    if (ip == ownIp) return DeviceKind.thisPhone;
    if (ip == gateway) return DeviceKind.router;
    if (open.contains(9100)) return DeviceKind.printer;
    return DeviceKind.generic;
  }

  /// тип по имени mDNS-сервиса (надёжнее портов)
  static DeviceKind? _kindFromService(String service) {
    if (service.contains('companion-link') ||
        service.contains('rdlink') ||
        service.contains('apple-mobdev')) {
      return DeviceKind.apple;
    }
    if (service.contains('airplay') || service.contains('raop')) {
      return DeviceKind.apple; // Apple TV / колонка
    }
    if (service.contains('googlecast')) return DeviceKind.tv;
    if (service.contains('printer') || service.contains('ipp')) {
      return DeviceKind.printer;
    }
    if (service.contains('smb') ||
        service.contains('workstation') ||
        service.contains('ssh')) {
      return DeviceKind.computer;
    }
    return null; // _http и прочее - неоднозначно
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

    // имена и типы по mDNS резолвим параллельно с портовым сканом
    final mdnsFuture = _resolveNames();

    await Future.wait([
      for (var h = 1; h <= 254; h++)
        () async {
          final ip = '$base.$h';
          final (open, refused) = await _probeHost(ip);
          if (open.isNotEmpty || refused || ip == ownIp) {
            found.add(LanDevice(
                ip, _classifyByPorts(ip, open, ownIp, gateway), open));
          }
          done++;
          onProgress?.call(done / 254);
        }()
    ]);

    // свой телефон мог не ответить на собственные подключения - добавим явно
    if (!found.any((d) => d.ip == ownIp)) {
      found.add(LanDevice(ownIp, DeviceKind.thisPhone, const []));
    }

    // подмешиваем имена и уточняем тип по mDNS (он надёжнее портов)
    final mdns = await mdnsFuture;
    final named = [
      for (final d in found)
        LanDevice(
          d.ip,
          // свой телефон и роутер не переопределяем
          (d.kind == DeviceKind.thisPhone || d.kind == DeviceKind.router)
              ? d.kind
              : (mdns[d.ip]?.kind ?? d.kind),
          d.openPorts,
          name: mdns[d.ip]?.name,
        )
    ]..sort((a, b) => a.lastOctet.compareTo(b.lastOctet));
    return (devices: named, subnet: '$base.0/24', noWifi: false);
  }

  /// имена устройств через Bonjour/NSD: ip -> дружелюбное имя. используем
  /// РОДНЫЕ API (NSNetServiceBrowser на iOS, NsdManager на Android) через пакет
  /// nsd - в отличие от «сырого» mDNS они работают на iOS с обычным разрешением
  /// локальной сети (NSLocalNetworkUsageDescription + NSBonjourServices),
  /// без спец-entitlement на multicast. best-effort - если не отвечает, молчим
  static Future<Map<String, ({String name, DeviceKind? kind})>>
      _resolveNames() async {
    final map = <String, ({String name, DeviceKind? kind})>{};
    const services = [
      '_companion-link._tcp', // iPhone/iPad/Mac
      '_airplay._tcp', // Apple TV, колонки
      '_raop._tcp', // AirPlay-аудио
      '_googlecast._tcp', // Chromecast, телевизоры
      '_smb._tcp', // компьютеры/NAS
      '_ipp._tcp', // принтеры
      '_printer._tcp',
      '_ssh._tcp',
      '_http._tcp', // роутеры/NAS
      '_workstation._tcp', // linux/windows-хосты
    ];
    // держим пару (тип сервиса, discovery), чтобы знать тип каждого устройства
    final entries = <(String, Discovery)>[];
    try {
      for (final s in services) {
        try {
          entries.add(
              (s, await startDiscovery(s, autoResolve: true, ipLookupType: IpLookupType.v4)));
        } catch (_) {/* сервис недоступен - пропускаем */}
      }
      // даём время на обнаружение и резолв адресов
      await Future.delayed(const Duration(seconds: 4));
      for (final (service, d) in entries) {
        final kind = _kindFromService(service);
        for (final svc in d.services) {
          final name = svc.name?.trim();
          if (name == null || name.isEmpty) continue;
          for (final addr in svc.addresses ?? const <InternetAddress>[]) {
            if (addr.type != InternetAddressType.IPv4) continue;
            final prev = map[addr.address];
            // имя ставим первое непустое; тип - первый определённый
            map[addr.address] = (
              name: prev?.name ?? name,
              kind: prev?.kind ?? kind,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('nsd: $e');
    } finally {
      for (final (_, d) in entries) {
        try {
          await stopDiscovery(d);
        } catch (_) {}
      }
    }
    return map;
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
