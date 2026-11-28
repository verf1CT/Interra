// ignore_for_file: invalid_use_of_visible_for_testing_member
// снимки экранов в демо-режиме для ревью дизайна (не входит в test/)
// запуск из app/:  SHOTS_DIR=путь flutter test tool/shots.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lk_interra/theme.dart';
import 'package:lk_interra/services/demo_mode.dart';
import 'package:lk_interra/screens/cabinet_screen.dart';
import 'package:lk_interra/screens/settings_screen.dart';
import 'package:lk_interra/screens/tariffs_screen.dart';
import 'package:lk_interra/screens/block_screen.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
  }
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final outDir = Platform.environment['SHOTS_DIR'] ?? 'build/shots';

  setUpAll(() async {
    Directory(outDir).createSync(recursive: true);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter';
    await _loadFont('MaterialIcons', [
      '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf'
    ]);
    final fonts = [
      for (final w in [400, 500, 600, 700, 800]) 'assets/fonts/Manrope-$w.ttf'
    ];
    for (final f in ['Manrope', 'Roboto', '.SF UI Text']) {
      await _loadFont(f, fonts);
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'qa_secret_demo_enabled_v2': true});
    FlutterSecureStorage.setMockInitialValues({});
    DemoMode.isEnabled.value = true;
  });

  // SHOTS_STORE=ios - 1290x2796 (App Store 6.9"), android - 1080x2160 (Google Play
  // и RuStore не берут кадр длиннее 2:1), без переменной - обычный айфон для ревью
  final (logical, dpr) = switch (Platform.environment['SHOTS_STORE']) {
    'ios' => (const Size(430, 932), 3.0),
    'android' => (const Size(400, 800), 2.7),
    _ => (const Size(393, 852), 2.0),
  };

  void setView(WidgetTester tester) {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  Future<void> snap(WidgetTester tester, GlobalKey key, String name) async {
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: dpr);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$outDir/$name.png').writeAsBytes(data!.buffer.asUint8List());
    });
  }

  Future<GlobalKey> open(WidgetTester tester, Brightness b, Widget home) async {
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(b),
        home: home,
      ),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    return key;
  }

  for (final b in Brightness.values) {
    final tag = b == Brightness.dark ? 'dark' : 'light';

    testWidgets('cabinet tabs $tag', (tester) async {
      setView(tester);

      final key = await open(tester, b, const CabinetScreen());
      await snap(tester, key, '1_home_$tag');

      // второй демо-договор - с долгом: проверяем состояние «ограничен»
      Future<void> frames() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      // вкладки снимаем на основном договоре, до переключения на должника
      const tabs = {'Услуги': '2_services', 'ТВ': '3_tv', 'История': '4_history'};
      for (final e in tabs.entries) {
        final finder = find.text(e.key);
        if (finder.evaluate().isEmpty) continue;
        await tester.tap(finder.last);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump();
        await snap(tester, key, '${e.value}_$tag');
      }
      await tester.tap(find.text('Главная').last);
      await frames();

      await tester.tap(find.text('Лицевой счёт 123456'));
      await frames();
      await snap(tester, key, '1_accounts_$tag');
      await tester.tap(find.text('Иванов И.И. (Дача)'));
      await frames();
      await snap(tester, key, '1_home_restricted_$tag');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tariffs $tag', (tester) async {
      setView(tester);

      final key = await open(tester, b, const TariffsScreen());
      await snap(tester, key, '6_tariffs_$tag');
      await tester.tap(find.text('Год+Квартал 100М'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await snap(tester, key, '6_tariff_sheet_$tag');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('block $tag', (tester) async {
      setView(tester);

      final key = await open(tester, b, const BlockScreen());
      await snap(tester, key, '7_block_$tag');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('payment $tag', (tester) async {
      setView(tester);
      Future<void> frames() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      // шторка поверх главной, как её видит абонент
      final key = await open(tester, b, const CabinetScreen());
      await tester.tap(find.text('Пополнить'));
      await frames();
      await snap(tester, key, '8_pay_$tag');
      await tester.tap(find.text('Банковская карта, SberPay, T-Pay, СБП'));
      await frames();
      await tester.enterText(find.byType(TextField), '1200');
      await frames();
      await snap(tester, key, '8_pay_amount_$tag');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('settings $tag', (tester) async {
      setView(tester);

      final key = await open(tester, b, const SettingsScreen());
      await snap(tester, key, '5_settings_$tag');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
