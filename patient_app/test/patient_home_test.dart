import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/main.dart';

void main() {
  Future<void> openPatientProfile(WidgetTester tester) async {
    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows all four profiles', (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp());

    expect(find.text('User'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('opens the user, doctor and admin workspaces', (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp());

    await tester.tap(find.text('User'));
    await tester.pumpAndSettle();
    expect(find.text('Care companion'), findsOneWidget);
    await tester.tap(find.byTooltip('Change profile'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Doctor'));
    await tester.pumpAndSettle();
    expect(find.text('Morning round'), findsOneWidget);
    await tester.tap(find.byTooltip('Change profile'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    expect(find.text('MACE Women’s Health Clinic'), findsOneWidget);
  });

  testWidgets('patient can submit a wellbeing check-in', (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp());
    await openPatientProfile(tester);

    await tester.tap(find.text('Check-in'));
    await tester.pumpAndSettle();
    expect(find.text('How are you feeling?'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Finish check-in'), 300);
    await tester.tap(find.text('Finish check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Thank you'), findsOneWidget);
  });

  testWidgets('SOS asks for confirmation', (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp());
    await openPatientProfile(tester);

    await tester.scrollUntilVisible(find.text('SOS - I need help'), 300);
    await tester.tap(find.text('SOS - I need help'));
    await tester.pumpAndSettle();
    expect(find.text('Help request confirmed'), findsOneWidget);
  });
}
