import 'package:flutter/material.dart';
import 'package:maatriwatch_patient_app/core/design_tokens.dart';


class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = MaatriTokens.statusColor(status);
    final label = switch (status) {
      'critical' => 'Critical',
      'warning' => 'Needs review',
      'info' => 'Information',
      'normal' => 'Stable',
      'open' => 'Open',
      'acknowledged' => 'Acknowledged',
      'escalated' => 'Escalated',
      'resolved' => 'Resolved',
      _ => status,
    };
    final icon = switch (status) {
      'critical' => Icons.warning_rounded,
      'warning' => Icons.priority_high_rounded,
      'normal' || 'resolved' => Icons.check_circle_rounded,
      'escalated' => Icons.north_east_rounded,
      'acknowledged' => Icons.visibility_rounded,
      _ => Icons.info_outline_rounded,
    };
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? MaatriTokens.space8 : MaatriTokens.space12,
          vertical: MaatriTokens.space4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(24.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: MaatriTokens.space4),
            Text(
              label,
              style: MaatriTokens.type(
                size: MaatriTokens.type12,
                weight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
