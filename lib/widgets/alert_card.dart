import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/alert_model.dart';
import '../utils/theme.dart';
import '../utils/helpers.dart';
import '../utils/constants.dart';

class AlertCard extends StatefulWidget {
  final AlertModel alert;
  final String? patientName;
  final VoidCallback? onViewPatient;
  final VoidCallback? onMarkResolved;

  const AlertCard({
    super.key,
    required this.alert,
    this.patientName,
    this.onViewPatient,
    this.onMarkResolved,
  });

  @override
  State<AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<AlertCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (AppHelpers.isCriticalAlert(widget.alert.type)) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCritical = AppHelpers.isCriticalAlert(widget.alert.type);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (ctx, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard.withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCritical
                  ? AppTheme.pink.withOpacity(0.3 + 0.3 * _pulse.value)
                  : AppTheme.pinkMuted.withOpacity(0.4),
              width: 1,
            ),
            boxShadow: isCritical
                ? [
                    BoxShadow(
                      color: AppTheme.pink.withOpacity(0.10 + 0.25 * _pulse.value),
                      blurRadius: 10 + 20 * _pulse.value,
                      spreadRadius: 2 * _pulse.value,
                    ),
                  ]
                : AppTheme.cardShadow,
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    AppHelpers.alertIcon(widget.alert.type),
                    color: AppTheme.error,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.patientName != null)
                        Text(widget.patientName!,
                            style: AppTheme.subhead.copyWith(fontSize: 14)),
                      Text(
                        AppHelpers.alertLabel(widget.alert.type),
                        style: AppTheme.body.copyWith(
                          color: AppTheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  AppHelpers.formatTimestamp(widget.alert.timestamp),
                  style: AppTheme.caption,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _vitalChip(Icons.favorite, '${widget.alert.heartRate.round()} BPM', AppTheme.error),
                const SizedBox(width: 8),
                _vitalChip(Icons.air, '${widget.alert.spo2.round()}%', AppTheme.pinkLight),
                const SizedBox(width: 8),
                _vitalChip(Icons.thermostat, '${widget.alert.temperature.toStringAsFixed(1)}°C', AppTheme.warning),
              ],
            ),
            if (widget.onViewPatient != null || widget.onMarkResolved != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (widget.onViewPatient != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onViewPatient,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.pinkLight,
                          side: BorderSide(color: AppTheme.pinkMuted),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Text('View Patient',
                            style: GoogleFonts.dmSans(fontSize: 12)),
                      ),
                    ),
                  if (widget.onViewPatient != null && widget.onMarkResolved != null)
                    const SizedBox(width: 8),
                  if (widget.onMarkResolved != null)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: widget.onMarkResolved,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success.withOpacity(0.2),
                          foregroundColor: AppTheme.success,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          elevation: 0,
                        ),
                        child: Text('Mark Resolved',
                            style: GoogleFonts.dmSans(fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vitalChip(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(value,
              style: GoogleFonts.dmSans(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
