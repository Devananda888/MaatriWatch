import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/core/patient_api.dart';
import 'package:maatriwatch_patient_app/features/patient/patient_home.dart';
import 'package:maatriwatch_patient_app/main.dart';

class _PatientApi extends PatientApi {
  _PatientApi({this.denied = false})
      : super(baseUrl: 'https://api.example/api/v1');

  final bool denied;

  @override
  Future<Map<String, dynamic>> home() async {
    if (denied) throw const PatientApiException('Account is not linked.', 403);
    return {
      'patient': {'full_name': 'Test Patient'},
      'latest_vital': {
        'heart_rate_bpm': 74,
        'spo2_percent': 98,
        'skin_adjacent_temperature_c': 35.8,
        'heart_rate_source': 'wearable_ppg',
        'spo2_source': 'wearable_ppg',
        'temperature_source': 'wearable_skin_adjacent',
        'observed_at': DateTime.now().toUtc().toIso8601String(),
        'freshness': 'current',
        'is_fresh': true,
      },
      'device_health': {'title': 'Wearable connected'},
      'care_plan': const [],
      'danger_signs': const [],
    };
  }

  @override
  Future<Map<String, dynamic>> consents() async => {'items': const []};
}

void main() {
  testWidgets('blocks use when the patient app has no secure configuration',
      (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp());
    await tester.pump();
    expect(find.text('MaatriWatch setup needed'), findsOneWidget);
    expect(
        find.textContaining('Do not use an unconfigured app'), findsOneWidget);
  });

  testWidgets('displays a supplied configuration error', (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp(
      initializationError: 'Secure configuration is required.',
    ));
    await tester.pump();
    expect(find.text('Secure configuration is required.'), findsOneWidget);
  });

  testWidgets('labels wearable readings with source and observation state',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: PatientHome(api: _PatientApi())));
    await tester.pumpAndSettle();
    expect(find.text('PPG-derived heart rate'), findsOneWidget);
    expect(find.textContaining('MAX30102 PPG'), findsWidgets);
    expect(find.text('Device / skin-adjacent temperature'), findsOneWidget);
  });

  testWidgets('shows an account-access state instead of offline fallback',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: PatientHome(api: _PatientApi(denied: true))));
    await tester.pumpAndSettle();
    expect(find.text('Account access needed'), findsOneWidget);
    expect(find.text('Account is not linked.'), findsOneWidget);
  });
}
