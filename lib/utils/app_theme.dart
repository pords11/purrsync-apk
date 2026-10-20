import 'package:flutter/material.dart';

/// Centralized "Warm, Playful, Premium" Design System for PurrSync.
/// Features bundled Nunito rounded typography, signature teal header gradient
/// (#1E5E57 → #2A6F68 → #3C8F85), unified status colors (#3DAE7C, #F2A33A, #E5534B),
/// 18–24px corner radii, and live Light / Dark mode support.
class AppTheme {
  AppTheme._();

  static bool isDark(BuildContext context) => false;

  // Core Light Palette (kept const for compile-time const widgets)
  static const Color background = Color(0xFFFAF8F5); // Warm alabaster / off-white
  static const Color surface = Color(0xFFFFFFFF); // Pure white for elevated cards
  static const Color surfaceMuted = Color(0xFFF3F1EC); // Soft card fill / input fill

  // Core Dark Palette
  static const Color darkBackground = Color(0xFF101716); // Warm deep obsidian teal
  static const Color darkSurface = Color(0xFF182220); // Elevated dark card surface
  static const Color darkSurfaceMuted = Color(0xFF212E2C); // Muted dark input fill
  static const Color darkBorder = Color(0xFF2B3B38);
  static const Color darkTextPrimary = Color(0xFFF3EFEA);
  static const Color darkTextSecondary = Color(0xFFA7B5B2);

  // Brand Teal Palette & Gradient (#1E5E57 → #2A6F68 → #3C8F85)
  static const Color primaryTealDark = Color(0xFF1E5E57);
  static const Color primaryTeal = Color(0xFF2A6F68); // Sophisticated Sage Teal
  static const Color primaryTealBright = Color(0xFF3C8F85);
  static const Color primaryTealLight = Color(0xFFE8F2F0);
  static const Color primary = primaryTeal;
  static const Color primarySubtle = primaryTealLight;

  static const LinearGradient tealHeaderGradient = LinearGradient(
    colors: [
      Color(0xFF1E5E57),
      Color(0xFF2A6F68),
      Color(0xFF3C8F85),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Unified Status Colors
  static const Color statusSafe = Color(0xFF3DAE7C); // Safe Green #3DAE7C
  static const Color statusSafeBg = Color(0xFFE6F6EE);
  static const Color statusWarning = Color(0xFFF2A33A); // Due-Soon Amber #F2A33A
  static const Color statusWarningBg = Color(0xFFFFF3E2);
  static const Color statusDanger = Color(0xFFE5534B); // Overdue Red #E5534B
  static const Color statusDangerBg = Color(0xFFFDECEB);

  // Warm Accents
  static const Color terracotta = Color(0xFFE07A5F); // Soft Terracotta
  static const Color warmPeach = Color(0xFFF2CC8F); // Warm Peach
  static const Color terracottaLight = Color(0xFFFDF0EC);

  static const Color textPrimary = Color(0xFF1D242B); // Deep Charcoal
  static const Color textSecondary = Color(0xFF6C757D); // Muted Slate
  static const Color textTertiary = Color(0xFF9AA1A9);
  static const Color textHint = textTertiary;

  static const Color borderLight = Color(0xFFEAEAEA); // 1px subtle card border
  static const Color dividerColor = Color(0xFFF0EFEB);

  // Portal Subtle Accent Tints
  static const Color ownerAccent = Color(0xFF2A6F68); // Sage Teal
  static const Color vetAccent = Color(0xFF3D6B8C); // Clinical Slate Blue
  static const Color clinicAccent = Color(0xFF4A7C59); // Botanical Evergreen

  // Context-aware helpers (always warm light boutique palette)
  static Color scaffoldBg(BuildContext context) => background;
  static Color cardSurface(BuildContext context) => surface;
  static Color mutedSurface(BuildContext context) => surfaceMuted;
  static Color border(BuildContext context) => borderLight;
  static Color dividerFor(BuildContext context) => borderLight;
  static Color primaryText(BuildContext context) => textPrimary;
  static Color textPrimaryColor(BuildContext context) => textPrimary;
  static Color secondaryText(BuildContext context) => textSecondary;
  static Color textSecondaryColor(BuildContext context) => textSecondary;

  // Soft shadows
  static List<BoxShadow> get softShadow => cardShadow;
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF1D242B).withValues(alpha: 0.05),
          blurRadius: 18,
          offset: const Offset(0, 5),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: const Color(0xFF1D242B).withValues(alpha: 0.02),
          blurRadius: 4,
          offset: const Offset(0, 1),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get elevatedShadow => [
        BoxShadow(
          color: const Color(0xFF1D242B).withValues(alpha: 0.09),
          blurRadius: 24,
          offset: const Offset(0, 8),
          spreadRadius: 0,
        ),
      ];

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: primaryTeal,
        onPrimary: Colors.white,
        primaryContainer: primaryTealLight,
        onPrimaryContainer: primaryTealDark,
        secondary: terracotta,
        onSecondary: Colors.white,
        secondaryContainer: terracottaLight,
        onSecondaryContainer: terracotta,
        surface: surface,
        onSurface: textPrimary,
        error: statusDanger,
        onError: Colors.white,
        outline: borderLight,
      ),
      fontFamily: 'Nunito',
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 18.5,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: textTertiary, fontSize: 14, fontFamily: 'Nunito'),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14, fontFamily: 'Nunito'),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.transparent, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryTeal, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: statusDanger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: statusDanger, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryTeal,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryTeal,
          side: const BorderSide(color: primaryTeal, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryTeal,
          textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: primaryTeal,
        labelColor: primaryTeal,
        unselectedLabelColor: textSecondary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: borderLight,
        labelStyle: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 14),
        unselectedLabelStyle: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w600, fontSize: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primaryTeal,
        unselectedItemColor: textSecondary,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w500, fontSize: 12),
      ),
      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: primaryTealBright,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFF1E443F),
        onPrimaryContainer: Color(0xFFD1ECE8),
        secondary: terracotta,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFF3E2723),
        onSecondaryContainer: warmPeach,
        surface: darkSurface,
        onSurface: darkTextPrimary,
        error: statusDanger,
        onError: Colors.white,
        outline: darkBorder,
      ),
      fontFamily: 'Nunito',
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF163D38),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 18.5,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: darkTextSecondary, fontSize: 14, fontFamily: 'Nunito'),
        labelStyle: const TextStyle(color: darkTextSecondary, fontSize: 14, fontFamily: 'Nunito'),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryTealBright, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: statusDanger, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryTealBright,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryTealBright,
          side: const BorderSide(color: primaryTealBright, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: primaryTealBright,
        unselectedItemColor: darkTextSecondary,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w500, fontSize: 12),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

/// Placeholder widget (Dark mode skipped per design specification).
class ThemeModeToggleButton extends StatelessWidget {
  final Color iconColor;
  const ThemeModeToggleButton({super.key, this.iconColor = Colors.white});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
