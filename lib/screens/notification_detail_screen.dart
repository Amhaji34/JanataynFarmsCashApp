import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

/// Shown when a push notification is tapped - a read-only detail view
/// built entirely from the notification's own payload (title/body are
/// pre-formatted server-side by the Postgres trigger that sent it, see
/// claude.md's "Push notifications" section), no extra network fetch
/// needed. Covers all four notification kinds: transaction, harvest,
/// harvest_sale, supplier_purchase.
class NotificationDetailScreen extends StatelessWidget {
  const NotificationDetailScreen({super.key, required this.data});

  /// The raw FCM data payload (all values are strings on the wire).
  /// Expected keys: kind, id, title, body, and (transaction only) type.
  final Map<String, String> data;

  IconData get _icon {
    switch (data['kind']) {
      case 'harvest':
        return Icons.eco_outlined;
      case 'harvest_sale':
        return Icons.sell_outlined;
      case 'supplier_purchase':
        return Icons.shopping_bag_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  Color get _color {
    switch (data['kind']) {
      case 'transaction':
        return AppColors.forType(data['type'] ?? '');
      case 'harvest':
      case 'harvest_sale':
        return AppColors.brandGreenLight;
      case 'supplier_purchase':
        return AppColors.expense;
      default:
        return AppColors.neutral;
    }
  }

  String get _kindLabel {
    switch (data['kind']) {
      case 'harvest':
        return 'Harvest';
      case 'harvest_sale':
        return 'Harvest sale';
      case 'supplier_purchase':
        return 'Supplier purchase';
      default:
        return 'Transaction';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = data['title'] ?? 'Notification';
    final body = data['body'] ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Notification')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: AppCard(
          accent: _color,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(icon: _icon, color: _color),
                  const SizedBox(width: 12),
                  Text(
                    _kindLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSecondary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: AppColors.inkSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
