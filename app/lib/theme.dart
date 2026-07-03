import 'package:flutter/material.dart';

/// фирменная палитра Интерры - единственный источник цветов для всего приложения.
/// стиль «чистый и воздушный»: белый фон, волосяные линии, цвет точечно
class AppColors {
  static const brand = Color(0xFF3A96D6); // фирменный синий
  static const brandInk = Color(0xFF206FA6); // синий потемнее для текста-акцента
  static const accent = Color(0xFFF77D31); // фирменный оранжевый
  static const danger = Color(0xFFD8362A); // ошибки
  static const ok = Color(0xFF2FA86A); // успех/статус

  static const bg = Color(0xFFFFFFFF); // фон экранов - белый
  static const surfaceAlt = Color(0xFFF3F6F9); // светлая заливка карточек
  static const line = Color(0xFFE4EAF0); // разделители

  static const ink = Color(0xFF12181D); // основной текст
  static const inkMute = Color(0xFF5C6B77); // вторичный текст
  static const inkFaint = Color(0xFF98A4AE); // третичный текст/иконки
}

/// единая карточка: светлая заливка без границ и теней
BoxDecoration cardBox({double radius = 16, Color? color}) => BoxDecoration(
      color: color ?? AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(radius),
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
    surface: AppColors.bg,
    onSurface: AppColors.ink,
  );
  const radius = 14.0;

  return ThemeData(
    useMaterial3: true,
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

    // светлая, «невесомая» шапка с тонкой линией снизу
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      shape: Border(bottom: BorderSide(color: AppColors.line)),
      iconTheme: IconThemeData(color: AppColors.ink),
    ),

    textTheme: const TextTheme(
      titleLarge: TextStyle(
          color: AppColors.ink, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(color: AppColors.ink, height: 1.35),
      bodySmall: TextStyle(color: AppColors.inkMute, height: 1.35),
    ),

    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.inkFaint,
      textColor: AppColors.ink,
      subtitleTextStyle: TextStyle(color: AppColors.inkMute, fontSize: 13),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // поля белые - чтобы выделяться внутри карточек со светлой заливкой
      fillColor: Colors.white,
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
        minimumSize: const Size.fromHeight(52),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.brandInk,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.brandInk),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.brand : const Color(0xFFD4DBE1)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
