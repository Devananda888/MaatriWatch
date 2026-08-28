import 'package:flutter_test/flutter_test.dart';
import 'package:maatriwatch_patient_app/main.dart';

void main() {
  testWidgets('shows the maternal care home and emergency pathway',
      (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp());
    await tester.pump();
    expect(find.text('Hello, Asha'), findsOneWidget);
    expect(find.text('Latest readings'), findsOneWidget);
    await tester.tap(find.text('Get help'));
    await tester.pumpAndSettle();
    expect(find.text('SOS — I need urgent help'), findsOneWidget);
    expect(find.text('Urgent warning signs'), findsOneWidget);
  });

  testWidgets('exposes care plan and consent controls', (tester) async {
    await tester.pumpWidget(const MaatriWatchPatientApp());
    await tester.pump();
    await tester.tap(find.text('Care plan'));
    await tester.pumpAndSettle();
    expect(find.text('Your care plan'), findsOneWidget);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Sharing choices'), findsOneWidget);
    expect(find.text('Wearable monitoring'), findsOneWidget);
  });
}
