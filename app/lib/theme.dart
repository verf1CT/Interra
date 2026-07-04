import 'package:flutter/material.dart';

/// фирменная палитра Интерры - единственный источник цветов для всего приложения.
/// стиль: светло-серый фон, белые карточки с мягкой тенью, шрифт Manrope,
/// фирменный синий - на действиях
class AppColors {
  static const brand = Color(0xFF3A96D6); // фирменный синий
  static const brandInk = Color(0xFF1F6FA6); // синий потемнее для текста-акцента
  static const accent = Color(0xFFF77D31); // фирменный оранжевый
  static const danger = Color(0xFFE23D2E); // ошибки
  static const ok = Color(0xFF23A06A); // успех/статус

  static const bg = Color(0xFFF4F6F9); // фон экранов - светло-серый
  static const card = Color(0xFFFFFFFF); // карточки - белые
  static const surfaceAlt = Color(0xFFEEF2F6); // подложка полей/чипов
  static const line = Color(0xFFE7ECF1); // разделители

  static const ink = Color(0xFF141A1F); // основной текст
  static const inkMute = Color(0xFF5A6773); // вторичный текст
  static const inkFaint = Color(0xFF98A5B0); // третичный текст/иконки

  static const _font = 'Manrope';
}

/// имя фирменного шрифта (для мест, где нужен явный fontFamily)
const String kFont = 'Manrope';

/// единая карточка: белая, с мягкой тенью и умеренным скруглением
BoxDecoration cardBox({double radius = 16, Color? color}) => BoxDecoration(
      color: color ?? AppColors.card,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F1B2733), // мягкая, едва заметная тень
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
        BoxShadow(
          color: Color(0x0A1B2733),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ],
    );

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
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
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

/// светлая тема приложения
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    primary: AppColors.brand,
    secondary: AppColors.accent,
    surface: AppColors.card,
    onSurface: AppColors.ink,
  );
  const radius = 12.0;

  return ThemeData(
    useMaterial3: true,
    fontFamily: AppColors._font,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    pageTransitionsTheme: appPageTransitions,
    splashFactory: InkSparkle.splashFactory,
    dividerColor: AppColors.line,
    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 1,
    ),

    // шапка сливается с фоном (без линии и тени) - крупный заголовок «парит»
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kFont,
        color: AppColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
      iconTheme: IconThemeData(color: AppColors.ink),
    ),

    textTheme: const TextTheme(
      titleLarge: TextStyle(
          color: AppColors.ink, fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleMedium: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(color: AppColors.ink, height: 1.35),
      bodySmall: TextStyle(color: AppColors.inkMute, height: 1.35),
      labelLarge: TextStyle(fontWeight: FontWeight.w700),
    ),

    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.inkFaint,
      textColor: AppColors.ink,
      titleTextStyle: TextStyle(
          fontFamily: kFont,
          color: AppColors.ink,
          fontSize: 15,
          fontWeight: FontWeight.w600),
      subtitleTextStyle: TextStyle(
          fontFamily: kFont, color: AppColors.inkMute, fontSize: 13),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      hintStyle: const TextStyle(color: AppColors.inkFaint),
      labelStyle: const TextStyle(color: AppColors.inkMute),
      prefixIconColor: AppColors.inkFaint,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(
            fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.brandInk,
        backgroundColor: AppColors.card,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(
            fontFamily: kFont, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brandInk,
        textStyle: const TextStyle(fontFamily: kFont, fontWeight: FontWeight.w700),
      ),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? AppColors.brand
              : const Color(0xFFCFD8E0)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}
