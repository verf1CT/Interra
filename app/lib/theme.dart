import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// фирменный шрифт
const String kFont = 'Manrope';

/// фирменные цвета - ОДИНАКОВЫЕ в светлой и тёмной теме (бренд и акценты)
class AppColors {
  static const brand = Color(0xFF3A96D6); // фирменный синий
  static const brandInk = Color(0xFF1F6FA6); // синий потемнее для акцент-текста
  static const accent = Color(0xFFF77D31); // фирменный оранжевый
  static const danger = Color(0xFFE23D2E); // ошибки
  static const ok = Color(0xFF23A06A); // успех/статус
  static const neutral = Color(0xFF8A97A2); // нейтральный серый, читаем на обеих темах
}

/// цвета поверхностей и текста - РАЗНЫЕ в светлой/тёмной теме.
/// доступ в виджетах через `context.p` (напр. `context.p.ink`)
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg; // фон экранов
  final Color card; // карточки
  final Color surfaceAlt; // подложка полей/чипов
  final Color line; // разделители/границы
  final Color ink; // основной текст
  final Color inkMute; // вторичный текст
  final Color inkFaint; // третичный текст/иконки

  const AppPalette({
    required this.bg,
    required this.card,
    required this.surfaceAlt,
    required this.line,
    required this.ink,
    required this.inkMute,
    required this.inkFaint,
  });

  static const light = AppPalette(
    bg: Color(0xFFF4F6F9),
    card: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEF2F6),
    line: Color(0xFFE7ECF1),
    ink: Color(0xFF141A1F),
    inkMute: Color(0xFF5A6773),
    inkFaint: Color(0xFF98A5B0),
  );

  static const dark = AppPalette(
    bg: Color(0xFF0F141A),
    card: Color(0xFF19212A),
    surfaceAlt: Color(0xFF232E39),
    line: Color(0xFF2C3742),
    ink: Color(0xFFEAEEF2),
    inkMute: Color(0xFF9BA8B4),
    inkFaint: Color(0xFF6C7A87),
  );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? card,
    Color? surfaceAlt,
    Color? line,
    Color? ink,
    Color? inkMute,
    Color? inkFaint,
  }) =>
      AppPalette(
        bg: bg ?? this.bg,
        card: card ?? this.card,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        line: line ?? this.line,
        ink: ink ?? this.ink,
        inkMute: inkMute ?? this.inkMute,
        inkFaint: inkFaint ?? this.inkFaint,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      line: Color.lerp(line, other.line, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMute: Color.lerp(inkMute, other.inkMute, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
    );
  }
}

/// быстрый доступ к палитре текущей темы
extension PaletteX on BuildContext {
  AppPalette get p => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

/// единая карточка: белая с мягкой тенью (светлая тема) либо приподнятая
/// поверхность с тонкой границей (тёмная - тени на тёмном не видны)
BoxDecoration cardBox(BuildContext context, {double radius = 16, Color? color}) {
  final p = context.p;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: color ?? p.card,
    borderRadius: BorderRadius.circular(radius),
    border: dark ? Border.all(color: p.line) : null,
    boxShadow: dark
        ? null
        : const [
            BoxShadow(
                color: Color(0x0F1B2733), blurRadius: 20, offset: Offset(0, 8)),
            BoxShadow(
                color: Color(0x0A1B2733), blurRadius: 2, offset: Offset(0, 1)),
          ],
  );
}

/// плавный переход между экранами: лёгкое появление + микро-сдвиг снизу
class _FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}

final PageTransitionsTheme appPageTransitions = PageTransitionsTheme(
  builders: {
    for (final platform in TargetPlatform.values)
      platform: const _FadeSlidePageTransitionsBuilder(),
  },
);

/// тема приложения для заданной яркости (светлая/тёмная)
ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final p = dark ? AppPalette.dark : AppPalette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: brightness,
    primary: AppColors.brand,
    secondary: AppColors.accent,
    surface: p.card,
    onSurface: p.ink,
    error: AppColors.danger,
  );
  const radius = 12.0;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: kFont,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    pageTransitionsTheme: appPageTransitions,
    splashFactory: InkSparkle.splashFactory,
    dividerColor: p.line,
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    extensions: [p],

    // шапка сливается с фоном (без линии и тени) - крупный заголовок «парит»
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kFont,
        color: p.ink,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      iconTheme: IconThemeData(color: p.ink),
    ),

    textTheme: TextTheme(
      titleLarge: TextStyle(
          color: p.ink, fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleMedium: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(color: p.ink, height: 1.35),
      bodySmall: TextStyle(color: p.inkMute, height: 1.35),
      labelLarge: const TextStyle(fontWeight: FontWeight.w700),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: p.inkFaint,
      textColor: p.ink,
      titleTextStyle: TextStyle(
          fontFamily: kFont,
          color: p.ink,
          fontSize: 15,
          fontWeight: FontWeight.w600),
      subtitleTextStyle:
          TextStyle(fontFamily: kFont, color: p.inkMute, fontSize: 13),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceAlt,
      hintStyle: TextStyle(color: p.inkFaint),
      labelStyle: TextStyle(color: p.inkMute),
      prefixIconColor: p.inkFaint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.brand.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(
            fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: dark ? AppColors.brand : AppColors.brandInk,
        backgroundColor: p.card,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: p.line),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(
            fontFamily: kFont, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? AppColors.brand : AppColors.brandInk,
        textStyle:
            const TextStyle(fontFamily: kFont, fontWeight: FontWeight.w700),
      ),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? AppColors.brand
              : (dark ? const Color(0xFF3A4652) : const Color(0xFFCFD8E0))),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

/// выбор оформления (Авто/Светлая/Тёмная), сохраняется между запусками
class ThemeController {
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);
  static const _key = 'theme_mode';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mode.value = _parse(prefs.getString(_key));
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, m.name);
  }

  static ThemeMode _parse(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String label(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Светлая',
        ThemeMode.dark => 'Тёмная',
        ThemeMode.system => 'Как в системе',
      };
}
