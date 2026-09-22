import 'package:flutter/material.dart';

/// Central design tokens for the app.
///
/// Colors are drawn from the Jannatein Agro Business logo — the deep forest
/// green of the wordmark, the tractor red, and the navy of the wheels — so the
/// UI reads as one brand family rather than default Material blue.
class AppColors {
  AppColors._();

  // ---- Brand ----------------------------------------------------------
  static const brandGreen = Color(0xFF1B5E3A);
  static const brandGreenDark = Color(0xFF134026);
  static const brandGreenDeep = Color(0xFF0F3D25);
  static const brandGreenLight = Color(0xFF2E8B57);
  static const brandRed = Color(0xFFB93B36);
  static const brandNavy = Color(0xFF1E3A5F);
  static const cream = Color(0xFFEEEFEA);

  // ---- Surfaces -------------------------------------------------------
  /// Page background — a soft, very slightly warm off-white.
  static const canvas = Color(0xFFF5F6F1);
  static const surface = Colors.white;
  static const hairline = Color(0xFFE7E8E1);
  static const fieldFill = Colors.white;

  // ---- Ink ------------------------------------------------------------
  static const ink = Color(0xFF16181A);
  static const inkSecondary = Color(0xFF5E635F);
  static const inkMuted = Color(0xFF8B8F8A);

  // ---- Transaction type accents --------------------------------------
  // Same semantic mapping the app has always used, just tuned to sit
  // together as a set rather than raw Material primaries.
  static const expense = Color(0xFFDC4A47);
  static const payroll = Color(0xFFE08526);
  static const loan = Color(0xFF3B7DD8);
  static const advance = Color(0xFF8257E5);
  static const cashIn = Color(0xFF2E9E5B);
  static const neutral = Color(0xFF8B8F8A);

  static const danger = Color(0xFFC0392B);

  /// Decorative palette for per-name badges (categories, staff, partners).
  /// Purely cosmetic — it encodes nothing, it just keeps lists lively.
  static const _namePalette = [
    Color(0xFF2E8B57), // green
    Color(0xFF3B7DD8), // blue
    Color(0xFFE08526), // orange
    Color(0xFF8257E5), // purple
    Color(0xFFDC4A47), // red
    Color(0xFF1E3A5F), // navy
    Color(0xFF109A8B), // teal
    Color(0xFFC2569B), // magenta
  ];

  /// Stable accent for a given name — same name always gets the same color,
  /// so a list doesn't repaint itself when an item is added.
  static Color accentFor(String key) =>
      _namePalette[key.hashCode.abs() % _namePalette.length];

  /// Accent color for a transaction `type` value from the database.
  static Color forType(String type) {
    switch (type) {
      case 'expense':
        return expense;
      case 'payroll':
        return payroll;
      case 'loan':
        return loan;
      case 'advance':
        return advance;
      case 'loan_repayment':
        return cashIn;
      case 'advance_deduction':
        return neutral;
      case 'transfer_in':
        return cashIn;
      case 'transfer_out':
        return brandNavy;
      default:
        return neutral;
    }
  }
}

/// Keyword-matched icons for expense categories, so "Fuel" and "Water" get
/// recognizable glyphs instead of a generic box.
class AppIcons {
  AppIcons._();

  static IconData forCategory(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('fuel') || lower.contains('gas')) {
      return Icons.local_gas_station_outlined;
    }
    if (lower.contains('water')) return Icons.water_drop_outlined;
    if (lower.contains('food') || lower.contains('meal')) {
      return Icons.restaurant_outlined;
    }
    if (lower.contains('seed') || lower.contains('feed')) {
      return Icons.grass_outlined;
    }
    if (lower.contains('tool') || lower.contains('equip')) {
      return Icons.build_outlined;
    }
    if (lower.contains('labor') || lower.contains('wage')) {
      return Icons.person_outline;
    }
    if (lower.contains('transport') || lower.contains('fare')) {
      return Icons.local_shipping_outlined;
    }
    if (lower.contains('meeting')) return Icons.groups_outlined;
    if (lower.contains('repair') || lower.contains('maintenance')) {
      return Icons.handyman_outlined;
    }
    if (lower.contains('electric') || lower.contains('power')) {
      return Icons.bolt_outlined;
    }
    if (lower.contains('rent')) return Icons.home_work_outlined;
    if (lower.contains('medic') || lower.contains('health')) {
      return Icons.medical_services_outlined;
    }
    return Icons.category_outlined;
  }
}

/// Shared elevation + shape values so cards look identical everywhere.
class AppStyles {
  AppStyles._();

  static const radiusCard = 16.0;
  static const radiusField = 14.0;
  static const radiusPill = 999.0;

  /// Soft, low-contrast lift. Deliberately subtle — depth, not drop shadow.
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 14,
      offset: const Offset(0, 4),
    ),
  ];

  static BoxDecoration get card => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(radiusCard),
    border: Border.all(color: AppColors.hairline),
    boxShadow: softShadow,
  );

  /// A card carrying a colored accent — used for stat tiles so each metric
  /// is identifiable at a glance without shouting.
  static BoxDecoration accentCard(Color accent) => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(radiusCard),
    border: Border.all(color: accent.withValues(alpha: 0.18)),
    boxShadow: softShadow,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandGreen,
      primary: AppColors.brandGreen,
      brightness: Brightness.light,
    ).copyWith(surface: AppColors.surface, error: AppColors.danger);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      fontFamily: null,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fieldFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.inkSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusField),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusField),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusField),
          borderSide: const BorderSide(
            color: AppColors.brandGreenLight,
            width: 1.6,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusField),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFC9CEC8),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.radiusField),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brandGreen,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.inkSecondary,
          side: const BorderSide(color: AppColors.hairline),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.radiusField),
          ),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brandGreen,
        foregroundColor: Colors.white,
        elevation: 3,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.brandGreen,
        side: const BorderSide(color: AppColors.hairline),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.inkSecondary,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const StadiumBorder(),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brandGreen,
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.inkSecondary,
        textColor: AppColors.ink,
      ),
    );
  }
}
