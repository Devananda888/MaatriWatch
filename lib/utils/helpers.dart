import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'constants.dart';

class AppHelpers {
  // ── TIME FORMATTING ───────────────────────────────────
  static String formatTimestamp(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('d MMM, HH:mm').format(dt);
  }

  static String formatDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('d MMM yyyy').format(dt);
  }

  static String formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('HH:mm').format(dt);
  }

  static String formatDateTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('d MMM yyyy, HH:mm').format(dt);
  }

  // ── VITAL STATUS ─────────────────────────────────────
  static String hrStatus(double hr, double baseline) {
    if (hr > AppConstants.hrHighThreshold ||
        (hr - baseline) > AppConstants.hrRiseThreshold) {
      return AppConstants.riskCritical;
    }
    if (hr > 90 || (hr - baseline) > 10) return AppConstants.riskWarning;
    return AppConstants.riskNormal;
  }

  static String spo2Status(double spo2) {
    if (spo2 < AppConstants.spo2LowThreshold) return AppConstants.riskCritical;
    if (spo2 < 96) return AppConstants.riskWarning;
    return AppConstants.riskNormal;
  }

  static String tempStatus(double temp, double baseline) {
    final diff = (temp - baseline).abs();
    if (diff > AppConstants.tempRiseThreshold) return AppConstants.riskCritical;
    if (diff > 1.5) return AppConstants.riskWarning;
    return AppConstants.riskNormal;
  }

  // ── COLOURS BY STATUS ────────────────────────────────
  static Color statusColor(String status) {
    switch (status) {
      case AppConstants.riskCritical: return AppTheme.error;
      case AppConstants.riskWarning:  return AppTheme.warning;
      default:                        return AppTheme.success;
    }
  }

  static Color riskColor(String? risk) {
    switch (risk) {
      case AppConstants.riskCritical: return AppTheme.error;
      case AppConstants.riskWarning:  return AppTheme.warning;
      default:                        return AppTheme.success;
    }
  }

  // ── ALERT ICON ───────────────────────────────────────
  static IconData alertIcon(String type) {
    switch (type) {
      case AppConstants.alertPphRisk:          return Icons.bloodtype;
      case AppConstants.alertPreeclampsiaRisk: return Icons.monitor_heart;
      case AppConstants.alertFallDetected:     return Icons.personal_injury;
      case AppConstants.alertSosManual:        return Icons.warning_rounded;
      case AppConstants.alertInfectionRisk:    return Icons.thermostat;
      default:                                 return Icons.notifications_active;
    }
  }

  static String alertLabel(String type) {
    switch (type) {
      case AppConstants.alertPphRisk:          return 'PPH Risk';
      case AppConstants.alertPreeclampsiaRisk: return 'Preeclampsia Risk';
      case AppConstants.alertFallDetected:     return 'Fall Detected';
      case AppConstants.alertSosManual:        return 'SOS Manual';
      case AppConstants.alertInfectionRisk:    return 'Infection Risk';
      default:                                 return type;
    }
  }

  static bool isCriticalAlert(String type) =>
      type == AppConstants.alertPphRisk || type == AppConstants.alertSosManual;

  // ── OVERALL PATIENT RISK ──────────────────────────────
  static String overallPatientRisk(double hr, double spo2, double temp,
      double baselineHR, double baselineTemp) {
    final statuses = [
      hrStatus(hr, baselineHR),
      spo2Status(spo2),
      tempStatus(temp, baselineTemp),
    ];
    if (statuses.contains(AppConstants.riskCritical)) {
      return AppConstants.riskCritical;
    }
    if (statuses.contains(AppConstants.riskWarning)) {
      return AppConstants.riskWarning;
    }
    return AppConstants.riskNormal;
  }

  // ── EPDS ─────────────────────────────────────────────
  static Color epdsScoreColor(int score) {
    if (score <= 9) return AppTheme.success;
    if (score <= 12) return AppTheme.warning;
    return AppTheme.error;
  }
}
