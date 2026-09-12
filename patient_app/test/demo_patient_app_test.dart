import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/main.dart';

void main() {
  testWidgets('demo login exposes the clearly labelled presentation account',
      (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp(demoMode: true));
    expect(find.text('DEMO'), findsOneWidget);
    expect(find.text('demo.patient@maatriwatch.local'), findsOneWidget);
    await tester.tap(find.text('Fill demo credentials'));
    await tester.tap(find.text('Sign in to demo'));
    await tester.pumpAndSettle();
    expect(find.text('Hello, Anjali'), findsOneWidget);
    expect(find.textContaining('Presentation mode'), findsOneWidget);
    expect(find.text('PPG-derived heart rate'), findsOneWidget);
    expect(find.text('118/76 mmHg'), findsOneWidget);
  });
}
