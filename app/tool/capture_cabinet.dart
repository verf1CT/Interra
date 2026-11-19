import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lk_interra/theme.dart';
import 'package:lk_interra/services/demo_mode.dart';
import 'package:lk_interra/screens/cabinet_screen.dart';

Future<void> loadFont(String family, List<String> paths) async {
  final fontLoader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      fontLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
  }
  await fontLoader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    const iconsPath = r'C:\src\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf';
    await loadFont('MaterialIcons', [iconsPath]);

    const manropeBase = r'c:\Users\ауыцфйыкенш\Documents\GitHub\interra\app\assets\fonts';
    const manropeFiles = [
      '$manropeBase\\Manrope-400.ttf',
      '$manropeBase\\Manrope-500.ttf',
      '$manropeBase\\Manrope-600.ttf',
      '$manropeBase\\Manrope-700.ttf',
      '$manropeBase\\Manrope-800.ttf',
    ];
    await loadFont('Manrope', manropeFiles);
    await loadFont('Roboto', manropeFiles);
    await loadFont('.SF UI Text', manropeFiles);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'qa_secret_demo_enabled_v2': true});
    DemoMode.isEnabled.value = true;
  });

  testWidgets('Capture light and dark cabinet screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393 * 2.0, 852 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const desktop = r'C:\Users\ауыцфйыкенш\Desktop';
    const brain = r'C:\Users\ауыцфйыкенш\.gemini\antigravity\brain\5c13197a-8667-4e80-aaa5-62a11a4bab87';

    // 1. Dark Mode
    final darkKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: darkKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.dark),
          home: const CabinetScreen(),
        ),
      ),
    );

    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.runAsync(() async {
      final darkBoundary = darkKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final darkImage = await darkBoundary.toImage(pixelRatio: 2.0);
      final darkByteData = await darkImage.toByteData(format: ui.ImageByteFormat.png);
      final darkBytes = darkByteData!.buffer.asUint8List();
      await File('$desktop\\cabinet_dark.png').writeAsBytes(darkBytes);
      await File('$brain\\cabinet_dark.png').writeAsBytes(darkBytes);
    });

    // 2. Light Mode
    final lightKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: lightKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          home: const CabinetScreen(),
        ),
      ),
    );

    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.runAsync(() async {
      final boundary = lightKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      await File('$desktop\\cabinet_light.png').writeAsBytes(bytes);
      await File('$brain\\cabinet_light.png').writeAsBytes(bytes);
    });

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
