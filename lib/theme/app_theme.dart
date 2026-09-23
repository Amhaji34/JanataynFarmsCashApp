import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Literal color values for one brightness - kept separate from
/// [AppColors] so [AppTheme.light]/[AppTheme.dark] can each build a
/// fully `const`-safe ThemeData from a fixed palette, instead of the
/// ambient (non-const, runtime-switchable) [AppColors] getters, which
/// would otherwise bake whichever mode happened to be active *when the
/// ThemeData was constructed* into both themes at once.
class _LightTokens {
  _LightTokens._();
  static const canvas = Color(0xFFF5F6F1);
  static const surface = Colors.white;
  static const hairline = Color(0xFFE7E8E1);
  static const fieldFill = Colors.white;
  static const ink = Color(0xFF16181A);
  static const inkSecondary = Color(0xFF5E635F);
  static const inkMuted = Color(0xFF8B8F8A);
  static const loan = Color(0xFF3B7DD8);
  static const advance = Color(0xFF8257E5);
}

class _DarkTokens {
  _DarkTokens._();
  static const canvas = Color(0xFF141613);
  static const surface = Color(0xFF1E211D);
  static const hairline = Color(0xFF32362F);
  static const fieldFill = Color(0xFF1E211D);
  static const ink = Color(0xFFF1F2EE);
  static const inkSecondary = Color(0xFFAEB3A9);
  static const inkMuted = Color(0xFF7C8177);
  // Brighter/lighter than the light-mode blue and purple - the light
  // variants read as muddy against a dark canvas/surface.
  static const loan = Color(0xFF6FA8FF);
  static const advance = Color(0xFFB18CFF);
}

/// Central design tokens for the app.
///
/// Colors are drawn from the Jannatein Agro Business logo — the deep forest
/// green of the wordmark, the tractor red, and the navy of the wheels — so the
/// UI reads as one brand family rather than default Material blue.
///
/// The "surface"/"ink" tokens plus `loan`/`advance` are the only ones
/// that differ between light and dark — the rest of the semantic
/// transaction colors and all brand colors stay the same in both
/// (they're already vivid enough to read on a dark canvas; blue and
/// purple weren't). [AppThemeController] flips [_dark] whenever the
/// effective brightness changes and triggers a full app rebuild, so
/// every widget re-reads these getters during that rebuild. Because a
/// runtime-switchable color can never be a Dart `const`, any widget
/// using one of these theme-aware tokens inside a `const` constructor
/// needs that `const` removed — everything else in this file
/// (brand/other semantic colors) is untouched and still `const`
/// everywhere it's used.
class AppColors {
  AppColors._();

  static bool _dark = false;

  // ---- Brand ------------------------------------------------------------
  static const brandGreen = Color(0xFF1B5E3A);
  static const brandGreenDark = Color(0xFF134026);
  static const brandGreenDeep = Color(0xFF0F3D25);
  static const brandGreenLight = Color(0xFF2E8B57);
  static const brandRed = Color(0xFFB93B36);
  static const brandNavy = Color(0xFF1E3A5F);
  static const cream = Color(0xFFEEEFEA);

  // ---- Surfaces (theme-aware) --------------------------------------------
  /// Page background.
  static Color get canvas => _dark ? _DarkTokens.canvas : _LightTokens.canvas;
  static Color get surface =>
      _dark ? _DarkTokens.surface : _LightTokens.surface;
  static Color get hairline =>
      _dark ? _DarkTokens.hairline : _LightTokens.hairline;
  static Color get fieldFill =>
      _dark ? _DarkTokens.fieldFill : _LightTokens.fieldFill;

  // ---- Ink (theme-aware) --------------------------------------------------
  static Color get ink => _dark ? _DarkTokens.ink : _LightTokens.ink;
  static Color get inkSecondary =>
      _dark ? _DarkTokens.inkSecondary : _LightTokens.inkSecondary;
  static Color get inkMuted =>
      _dark ? _DarkTokens.inkMuted : _LightTokens.inkMuted;

  // ---- Transaction type accents --------------------------------------
  // Same semantic mapping the app has always used, just tuned to sit
  // together as a set rather than raw Material primaries. loan/advance
  // are theme-aware (see _LightTokens/_DarkTokens) since the light-mode
  // blue/purple read poorly against a dark canvas; the rest are vivid
  // enough to stay the same in both themes.
  static const expense = Color(0xFFDC4A47);
  static const payroll = Color(0xFFE08526);
  static Color get loan => _dark ? _DarkTokens.loan : _LightTokens.loan;
  static Color get advance =>
      _dark ? _DarkTokens.advance : _LightTokens.advance;
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
  /// A black shadow does nothing useful on a dark canvas, so dark mode
  /// relies on the hairline border alone for card separation instead.
  static List<BoxShadow> get softShadow => AppColors._dark
      ? const []
      : [
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

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final canvas = isDark ? _DarkTokens.canvas : _LightTokens.canvas;
    final surface = isDark ? _DarkTokens.surface : _LightTokens.surface;
    final hairline = isDark ? _DarkTokens.hairline : _LightTokens.hairline;
    final fieldFill = isDark ? _DarkTokens.fieldFill : _LightTokens.fieldFill;
    final ink = isDark ? _DarkTokens.ink : _LightTokens.ink;
    final inkSecondary = isDark
        ? _DarkTokens.inkSecondary
        : _LightTokens.inkSecondary;
    final inkMuted = isDark ? _DarkTokens.inkMuted : _LightTokens.inkMuted;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandGreen,
      primary: AppColors.brandGreen,
      brightness: brightness,
    ).copyWith(surface: surface, error: AppColors.danger, onSurface: ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      fontFamily: null,

      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: inkMuted, fontSize: 14),
        labelStyle: TextStyle(color: inkSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusField),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusField),
          borderSide: BorderSide(color: hairline),
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
          borderSide: BorderSide(color: hairline),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: isDark
              ? const Color(0xFF3A3F37)
              : const Color(0xFFC9CEC8),
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
          foregroundColor: AppColors.brandGreenLight,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: inkSecondary,
          side: BorderSide(color: hairline),
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
        backgroundColor: surface,
        selectedColor: AppColors.brandGreen,
        side: BorderSide(color: hairline),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: inkSecondary,
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

      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brandGreen,
      ),

      listTileTheme: ListTileThemeData(iconColor: inkSecondary, textColor: ink),
    );
  }
}

/// Controls light/dark/system and persists the choice. `AppColors`'
/// theme-aware getters read [AppColors._dark] directly (updated by this
/// controller), so every widget that reads them during a rebuild gets
/// the right color — see the note on [AppColors] for why that can't be
/// a `const`-compatible `InheritedWidget`/`Theme.of(context)` lookup
/// given how pervasively this app's screens reference `AppColors.x`
/// with no `BuildContext` at hand.
class AppThemeController extends ChangeNotifier {
  AppThemeController._();
  static final instance = AppThemeController._();

  static const _prefsKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  /// Loads the persisted choice (defaults to "system") and applies it.
  /// Call once, before the first frame.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      _mode = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {
      _mode = ThemeMode.system;
    }
    _applyBrightness();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    _applyBrightness();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // Best-effort: worst case the choice doesn't survive a restart.
    }
  }

  /// Re-resolves brightness when in "system" mode and the OS brightness
  /// changes - see main.dart's WidgetsBindingObserver, which calls this.
  void refreshSystemBrightness() {
    if (_mode != ThemeMode.system) return;
    _applyBrightness();
    notifyListeners();
  }

  void _applyBrightness() {
    final dark = switch (_mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        SchedulerBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
    AppColors._dark = dark;
  }
}
