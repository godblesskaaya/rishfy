import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Rishfy theme — Material 3 with a teal-forward palette.
///
/// Primary (teal) evokes coastal Tanzania; secondary (warm amber) signals
/// energy and motion. Both work in light and dark modes.
class AppTheme {
  AppTheme._();

  // -------- Brand palette --------
  static const Color _primaryTeal = Color(0xFF008080); // Rishfy teal
  static const Color _primaryTealDark = Color(0xFF006666);
  static const Color _accentAmber = Color(0xFFFFA726);
  static const Color _successGreen = Color(0xFF16A34A);
  static const Color _errorRed = Color(0xFFDC2626);
  static const Color _warnOrange = Color(0xFFEA580C);
  static const Color _neutralBg = Color(0xFFF8FAFC);
  static const Color _neutralBgDark = Color(0xFF0F172A);

  // ==========================================================================
  // Light
  // ==========================================================================
  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _primaryTeal,
      primary: _primaryTeal,
      secondary: _accentAmber,
      error: _errorRed,
      surface: Colors.white,
      brightness: Brightness.light,
    );

    return _base(scheme, _neutralBg);
  }

  // ==========================================================================
  // Dark
  // ==========================================================================
  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _primaryTealDark,
      primary: _primaryTeal,
      secondary: _accentAmber,
      error: _errorRed,
      surface: const Color(0xFF1E293B),
      brightness: Brightness.dark,
    );

    return _base(scheme, _neutralBgDark);
  }

  // ==========================================================================
  // Base theme factory
  // ==========================================================================
  static ThemeData _base(ColorScheme scheme, Color background) {
    final bool isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Inter',
      visualDensity: VisualDensity.standard,

      // ---- AppBar ----
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),

      // ---- Buttons ----
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMd),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // ---- Input ----
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHighest
            : scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMd,
          vertical: AppConstants.spaceMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
      ),

      // ---- Cards ----
      cardTheme: CardTheme(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),

      // ---- Bottom Nav ----
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // ---- Chips ----
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primary.withValues(alpha: 0.12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceMd,
          vertical: AppConstants.spaceXs,
        ),
      ),

      // ---- Semantic colors ----
      extensions: <ThemeExtension<dynamic>>[
        AppSemanticColors(
          success: _successGreen,
          warning: _warnOrange,
          info: scheme.primary,
        ),
      ],
    );
  }
}

/// Semantic colors not covered by ColorScheme (success, warning, info).
/// Access via `Theme.of(context).extension<AppSemanticColors>()!`
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.info,
  });

  final Color success;
  final Color warning;
  final Color info;

  @override
  AppSemanticColors copyWith({Color? success, Color? warning, Color? info}) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      info: Color.lerp(info, other.info, t) ?? info,
    );
  }
}
