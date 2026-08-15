import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'features/profiles/role_selection_page.dart';

void main() => runApp(const MaatriWatchPatientApp());

/// Android-first entry point for the MaatriWatch companion app.
class MaatriWatchPatientApp extends StatelessWidget {
  const MaatriWatchPatientApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MaatriWatch',
        debugShowCheckedModeBanner: false,
        theme: maatriTheme(),
        home: const RoleSelectionPage(),
      );
}
