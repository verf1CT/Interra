// приёмник дампов кабинета на компьютере разработчика. телефон в той же
// wi-fi сети шлёт дамп POST-запросом, файл ложится в папку ~/interra-dumps.
//
//   dart tool/dump_server.dart [порт]
//
// при первом запуске Windows спросит доступ к сети - разрешить для частных сетей
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args.first) : 8787;
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
  final dir = Directory('$home${Platform.pathSeparator}interra-dumps')..createSync(recursive: true);

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  final ips = [
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
      for (final a in i.addresses)
        if (!a.isLoopback) '${a.address}:$port (${i.name})',
  ];
  stdout.writeln('жду дампы, адрес для приложения:\n  ${ips.join('\n  ')}');
  stdout.writeln('папка: ${dir.path}');

  await for (final req in server) {
    if (req.method != 'POST') {
      req.response
        ..statusCode = HttpStatus.ok
        ..write('interra dump receiver');
      await req.response.close();
      continue;
    }
    try {
      final body = await utf8.decoder.bind(req).join();
      final t = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final name = 'dump-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}.txt';
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(body);
      stdout.writeln('${two(t.hour)}:${two(t.minute)} принят ${(body.length / 1024).round()} КБ -> ${file.path}');
      req.response.statusCode = HttpStatus.ok;
      req.response.write('ok');
    } catch (e) {
      stderr.writeln('ошибка: $e');
      req.response.statusCode = HttpStatus.internalServerError;
    }
    await req.response.close();
  }
}
