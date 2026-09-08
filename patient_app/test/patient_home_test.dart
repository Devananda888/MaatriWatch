import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/main.dart';

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
}
