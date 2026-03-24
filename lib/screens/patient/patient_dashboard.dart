import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../utils/theme.dart';
import '../../widgets/floating_pill_nav.dart';
import 'vitals_tab.dart';
import 'maatricare_tab.dart';
import 'screening_tab.dart';
import 'patient_profile_tab.dart';

class PatientDashboard extends StatefulWidget {
  final UserModel? userModel;
  final bool demoMode;

  const PatientDashboard({super.key, this.userModel, this.demoMode = false});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  int _currentIndex = 0;

  static const List<FloatingNavItem> _navItems = [
    FloatingNavItem(icon: Icons.monitor_heart_outlined, activeIcon: Icons.monitor_heart, label: 'My Vitals'),
    FloatingNavItem(icon: Icons.self_improvement_outlined, activeIcon: Icons.self_improvement, label: 'MaatriCare'),
    FloatingNavItem(icon: Icons.assignment_outlined, activeIcon: Icons.assignment, label: 'Screening'),
    FloatingNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final patientId = widget.userModel?.patientId ?? 'demo_priya';

    final tabs = [
      VitalsTab(patientId: patientId, demoMode: widget.demoMode),
      MaatricareTab(patientId: patientId, demoMode: widget.demoMode),
      ScreeningTab(patientId: patientId, demoMode: widget.demoMode),
      PatientProfileTab(userModel: widget.userModel, demoMode: widget.demoMode),
    ];

    return Scaffold(
      backgroundColor: AppTheme.patientBg,
      body: tabs[_currentIndex],
      bottomNavigationBar: FloatingPillNav(
        currentIndex: _currentIndex,
        items: _navItems,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}
