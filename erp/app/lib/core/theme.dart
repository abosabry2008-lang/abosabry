import 'package:flutter/material.dart';

/// SAP Fiori-inspired Material 3 theme for the ERP client.
///
/// This changes the visual language only (colours, radii, density, borders) —
/// no behaviour or data is affected.
class AppTheme {
  AppTheme._();

  /// SAP Fiori signature blue.
  static const Color seed = Color(0xFF0A6ED1);

  /// Dark shell bar used by SAP Fiori launchpad / GUI title bars.
  static const Color shellBar = Color(0xFF354A5F);

  static const Color lightBackground = Color(0xFFF5F6F7);
  static const Color fioriBorder = Color(0xFFD9D9D9);
  static const Color fioriHeader = Color(0xFF354A5F);

  /// Tinted band used by section / group headers.
  static const Color sectionHeader = Color(0xFFEBF1F7);

  /// Header row of analytical tables (SAP ALV style).
  static const Color tableHeader = Color(0xFFE4EBF3);

  static const Color textPrimary = Color(0xFF1D2D3E);
  static const Color textSecondary = Color(0xFF5A6A7A);

  static const Color warning = Color(0xFFB26A00);
  static const Color success = Color(0xFF2E7D32);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static bool isLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  /// Background for a section header band.
  static Color sectionHeaderColor(BuildContext context) => isLight(context)
      ? sectionHeader
      : Theme.of(context).colorScheme.surfaceContainerHigh;

  /// Background for a table heading row.
  static Color tableHeaderColor(BuildContext context) => isLight(context)
      ? tableHeader
      : Theme.of(context).colorScheme.surfaceContainerHighest;

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    ).copyWith(
      primary: isLight ? seed : const Color(0xFF7FB8F0),
      surface: isLight ? Colors.white : const Color(0xFF1C2229),
    );

    final border = isLight ? fioriBorder : scheme.outlineVariant;
    final text = isLight ? textPrimary : scheme.onSurface;
    final secondaryText = isLight ? textSecondary : scheme.onSurfaceVariant;

    const radius = BorderRadius.all(Radius.circular(4));
    const cardRadius = BorderRadius.all(Radius.circular(6));
    const controlSize = Size(0, 34);

    final typography = Typography.material2021(
      platform: TargetPlatform.android,
      colorScheme: scheme,
    );
    final baseText = isLight ? typography.black : typography.white;

    final textTheme = baseText.copyWith(
      headlineSmall: baseText.headlineSmall
          ?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, color: text),
      titleLarge: baseText.titleLarge
          ?.copyWith(fontSize: 19, fontWeight: FontWeight.w600, color: text),
      titleMedium: baseText.titleMedium
          ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: text),
      titleSmall: baseText.titleSmall
          ?.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: text),
      bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 14, color: text),
      bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 13, color: text),
      bodySmall: baseText.bodySmall
          ?.copyWith(fontSize: 11.5, color: secondaryText),
      labelLarge: baseText.labelLarge
          ?.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: text),
      labelMedium: baseText.labelMedium?.copyWith(fontSize: 12, color: text),
      labelSmall: baseText.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: secondaryText,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: isLight ? lightBackground : scheme.surface,
      canvasColor: isLight ? Colors.white : scheme.surface,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? shellBar : const Color(0xFF22303D),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 50,
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 20),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? Colors.white : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: cardRadius,
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: isLight ? Colors.white : scheme.surfaceContainerHighest,
        border: const OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        labelStyle: TextStyle(fontSize: 12.5, color: secondaryText),
        floatingLabelStyle: TextStyle(fontSize: 12.5, color: scheme.primary),
        hintStyle: TextStyle(fontSize: 12.5, color: secondaryText),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: controlSize,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: controlSize,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: controlSize,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(34, 34),
          padding: const EdgeInsets.all(6),
          shape: const RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        minVerticalPadding: 4,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: text,
        ),
        subtitleTextStyle: TextStyle(fontSize: 11.5, color: secondaryText),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(
        color: border,
        space: 1,
        thickness: 1,
      ),
      dataTableTheme: DataTableThemeData(
        decoration: BoxDecoration(
          border: Border.all(color: border),
        ),
        headingRowColor: WidgetStatePropertyAll<Color>(
          isLight ? tableHeader : scheme.surfaceContainerHighest,
        ),
        headingTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isLight ? textPrimary : scheme.onSurface,
        ),
        dataTextStyle: TextStyle(
          fontSize: 12.5,
          color: isLight ? textPrimary : scheme.onSurface,
        ),
        headingRowHeight: 34,
        dataRowMinHeight: 30,
        dataRowMaxHeight: 40,
        horizontalMargin: 10,
        columnSpacing: 20,
        dividerThickness: 0.5,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surface,
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 19),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 19,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12.5,
        ),
        indicatorColor: scheme.primary.withAlpha(24),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surface,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isLight ? Colors.white : scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        surfaceTintColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: border),
        labelStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
        decoration: BoxDecoration(
          color: shellBar.withAlpha(235),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.all(
          (isLight ? textSecondary : scheme.onSurfaceVariant).withAlpha(90),
        ),
      ),
    );
  }
}
