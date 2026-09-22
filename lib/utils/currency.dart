import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

/// The two currencies this app tracks, side by side with no exchange
/// rate — every balance/aggregate in the app is computed once per
/// currency and the two numbers are shown separately, never blended.
enum AppCurrency {
  usd('USD', '\$', 2, 'US Dollar'),
  slsh('SLSH', 'Sl', 0, 'Somaliland Shilling');

  const AppCurrency(this.code, this.symbol, this.decimalDigits, this.label);

  /// Stored verbatim in the `currency` column of every money-bearing row.
  final String code;
  final String symbol;
  final int decimalDigits;
  final String label;

  NumberFormat get _formatter =>
      NumberFormat.currency(symbol: '$symbol ', decimalDigits: decimalDigits);

  String format(double amount) => _formatter.format(amount);

  static AppCurrency fromCode(String? code) {
    switch (code) {
      case 'SLSH':
        return AppCurrency.slsh;
      case 'USD':
      default:
        return AppCurrency.usd;
    }
  }
}

/// The single place every screen formats a money amount, instead of each
/// declaring its own `NumberFormat.currency`. Centralizes the SLSH
/// display convention (e.g. "Sl 1,234,567") so it's a one-file change if
/// the format ever needs adjusting.
String formatMoney(double amount, AppCurrency currency) =>
    currency.format(amount);

/// Two-segment pill for picking a currency on an entry form — visually
/// matches the app's existing toggle patterns (the direction toggle in
/// transfer_funds_screen.dart, the type chips in report_screen.dart).
class CurrencyToggle extends StatelessWidget {
  const CurrencyToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AppCurrency value;
  final ValueChanged<AppCurrency> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final currency in AppCurrency.values) ...[
          if (currency != AppCurrency.values.first) const SizedBox(width: 10),
          Expanded(child: _segment(currency)),
        ],
      ],
    );
  }

  Widget _segment(AppCurrency currency) {
    final selected = currency == value;
    return Material(
      color: selected
          ? AppColors.brandGreen.withValues(alpha: 0.10)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(AppStyles.radiusField),
      child: InkWell(
        onTap: () => onChanged(currency),
        borderRadius: BorderRadius.circular(AppStyles.radiusField),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppStyles.radiusField),
            border: Border.all(
              color: selected
                  ? AppColors.brandGreen.withValues(alpha: 0.45)
                  : AppColors.hairline,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            currency.code,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.brandGreen : AppColors.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders one amount per currency, stacked, for stats that must show
/// both currencies at once (dashboard, account balances, owed badges).
/// A currency line is skipped when its amount is exactly zero, unless
/// every currency is zero (then USD alone is shown as "$0.00") — so a
/// business that has only ever used one currency doesn't get a
/// permanent, meaningless "Sl 0" line.
class DualCurrencyStat extends StatelessWidget {
  const DualCurrencyStat({
    super.key,
    required this.amounts,
    this.style,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.spacing = 2,
  });

  /// One entry per currency to display.
  final Map<AppCurrency, double> amounts;
  final TextStyle? style;
  final CrossAxisAlignment crossAxisAlignment;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final nonZero = amounts.entries
        .where((e) => e.value.abs() > 0.004)
        .toList();
    final toShow = nonZero.isEmpty
        ? [MapEntry(AppCurrency.usd, amounts[AppCurrency.usd] ?? 0)]
        : nonZero;

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < toShow.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          Text(formatMoney(toShow[i].value, toShow[i].key), style: style),
        ],
      ],
    );
  }
}
