import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_clinician_dashboard/core/models.dart';
import 'package:maatriwatch_clinician_dashboard/core/runtime_config.dart';
import 'package:maatriwatch_clinician_dashboard/widgets/vital_trend_chart.dart';

void main() {
  test('dashboard blocks an absent API endpoint', () {
    expect(DashboardRuntimeConfig.validationError(), isNotNull);
  });

  test('a reading without a validated BP source cannot appear in BP trends', () {
    final reading = VitalReading.fromJson({
      'captured_at': '2026-09-08T10:00:00Z',
      'systolic_bp': 180,
      'diastolic_bp': 120,
    });
    expect(reading.bloodPressureSource, isNull);
    expect(VitalMetric.systolic.value(reading), isNull);
  });

  test('measurement metadata includes provenance and freshness', () {
    final reading = VitalReading.fromJson({
      'observed_at': '2026-09-08T10:00:00Z',
      'heart_rate_bpm': 75,
      'heart_rate_source': 'wearable_ppg',
      'freshness': 'stale',
    });
    expect(reading.heartRateSource, 'wearable_ppg');
    expect(reading.observationStatus, 'stale');
  });

  test('patient detail retains the assigned watch identifier', () {
    final detail = PatientDetail.fromJson({
      'patient': {
        'id': 'patient-1',
        'full_name': 'Presentation patient',
        'medical_record_number': 'MW-001',
      },
      'device': {
        'id': '5b9ebccd-a951-47f9-8a89-15b7fafa346a',
        'serial_number': 'MW-XIAO-001',
        'firmware_version': '1.0.0',
        'last_seen_at': '2026-09-12T05:55:00Z',
      },
    });

    expect(detail.device?.id, '5b9ebccd-a951-47f9-8a89-15b7fafa346a');
    expect(detail.device?.serialNumber, 'MW-XIAO-001');
  });
}
