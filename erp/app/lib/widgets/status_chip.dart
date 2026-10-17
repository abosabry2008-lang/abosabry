import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/l10n.dart';

/// A coloured chip that renders a business status value.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.label,
    this.compact = false,
  });

  final String status;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = Formatters.statusColor(context, status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Formatters.statusIcon(status), size: compact ? 12 : 14, color: color),
          const SizedBox(width: 6),
          Text(
            label ?? context.s.status(status),
            style: TextStyle(
              color: color,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
