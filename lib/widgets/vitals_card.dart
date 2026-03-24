import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/theme.dart';

class VitalsCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String status;
  final IconData icon;
  final String? normalRange;
  final bool showTrendUp;

  const VitalsCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
    required this.icon,
    this.normalRange,
    this.showTrendUp = false,
  });

  Color get _statusColor {
    switch (status) {
      case 'critical': return AppTheme.error;
      case 'warning':  return AppTheme.warning;
      default:         return AppTheme.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: color, width: 3),
          top: BorderSide(color: AppTheme.pinkMuted.withOpacity(0.3), width: 1),
          right: BorderSide(color: AppTheme.pinkMuted.withOpacity(0.3), width: 1),
          bottom: BorderSide(color: AppTheme.pinkMuted.withOpacity(0.3), width: 1),
        ),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(unit, style: AppTheme.caption),
              ),
              const Spacer(),
              Icon(
                showTrendUp ? Icons.trending_up : Icons.trending_flat,
                color: color,
                size: 18,
              ),
            ],
          ),
          if (normalRange != null) ...[
            const SizedBox(height: 4),
            Text(
              'Normal: $normalRange',
              style: AppTheme.caption.copyWith(fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}
