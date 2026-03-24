import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../utils/theme.dart';
import '../../widgets/floating_pill_nav.dart';
import 'patients_tab.dart';
import 'alerts_tab.dart';
import 'analytics_tab.dart';
import 'doctor_profile_tab.dart';

class DoctorDashboard extends StatefulWidget {
  final UserModel? userModel;
  final bool demoMode;

  const DoctorDashboard({super.key, this.userModel, this.demoMode = false});

  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  int _currentIndex = 0;

  static const List<FloatingNavItem> _navItems = [
    FloatingNavItem(icon: Icons.people_outline, activeIcon: Icons.people, label: 'Patients'),
    FloatingNavItem(icon: Icons.notifications_none, activeIcon: Icons.notifications, label: 'Alerts'),
    FloatingNavItem(icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: 'Analytics'),
    FloatingNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final doctorName = widget.userModel?.name ?? (widget.demoMode ? 'Demo' : 'Doctor');
    final doctorId = widget.userModel?.uid ?? 'demo_doctor';

    final tabs = [
      PatientsTab(doctorId: doctorId, doctorName: doctorName, demoMode: widget.demoMode),
      AlertsTab(doctorId: doctorId, demoMode: widget.demoMode),
      AnalyticsTab(doctorId: doctorId, demoMode: widget.demoMode),
      DoctorProfileTab(userModel: widget.userModel, demoMode: widget.demoMode),
    ];

    return Scaffold(
      backgroundColor: AppTheme.doctorBg,
      body: tabs[_currentIndex],
      bottomNavigationBar: FloatingPillNav(
        currentIndex: _currentIndex,
        items: _navItems,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}
