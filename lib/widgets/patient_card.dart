import 'package:flutter/material.dart';
import '../models/patient_model.dart';
import '../utils/theme.dart';
import '../utils/helpers.dart';
import 'risk_badge.dart';

class PatientCard extends StatelessWidget {
  final PatientModel patient;
  final double? heartRate;
  final double? spo2;
  final double? temperature;
  final int? lastUpdated;
  final VoidCallback? onTap;

  const PatientCard({
    super.key,
    required this.patient,
    this.heartRate,
    this.spo2,
    this.temperature,
    this.lastUpdated,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.pinkMuted.withOpacity(0.3),
                  child: Text(
                    patient.name.isNotEmpty ? patient.name[0].toUpperCase() : '?',
                    style: AppTheme.subhead.copyWith(
                        color: AppTheme.pinkLight, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(patient.name, style: AppTheme.subhead),
                      Text(
                        '${patient.age} years • ${patient.deviceId}',
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
                RiskBadge(level: patient.riskLevel),
              ],
            ),
            if (heartRate != null || spo2 != null || temperature != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (heartRate != null) _chip('❤️', '${heartRate!.round()} BPM'),
                  if (spo2 != null) ...[
                    const SizedBox(width: 8),
                    _chip('💨', '${spo2!.round()}%'),
                  ],
                  if (temperature != null) ...[
                    const SizedBox(width: 8),
                    _chip('🌡️', '${temperature!.toStringAsFixed(1)}°C'),
                  ],
                  const Spacer(),
                  if (lastUpdated != null)
                    Text(
                      AppHelpers.formatTimestamp(lastUpdated!),
                      style: AppTheme.caption,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String emoji, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.pinkMuted.withOpacity(0.3)),
      ),
      child: Text(
        '$emoji $text',
        style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
      ),
    );
  }
}
