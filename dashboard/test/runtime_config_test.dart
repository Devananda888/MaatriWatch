import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_clinician_dashboard/core/models.dart';
import 'package:maatriwatch_clinician_dashboard/core/runtime_config.dart';

void main() {
  test('dashboard blocks an absent API endpoint', () {
    expect(DashboardRuntimeConfig.validationError(), isNotNull);
  });

  test('a reading without a validated BP source retains no BP authority', () {
    final reading = VitalReading.fromJson({
      'captured_at': '2026-09-08T10:00:00Z',
      'systolic_bp': 180,
      'diastolic_bp': 120,
    });
    expect(reading.bloodPressureSource, isNull);
    expect(reading.systolic, 180);
  });
}
