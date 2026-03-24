import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../utils/theme.dart';
import '../../utils/helpers.dart';
import '../auth/login_screen.dart';

class PatientProfileTab extends StatelessWidget {
  final UserModel? userModel;
  final bool demoMode;

  const PatientProfileTab({super.key, this.userModel, this.demoMode = false});

  @override
  Widget build(BuildContext context) {
    final name = userModel?.name ?? 'Priya Sharma';
    final email = userModel?.email ?? 'priya@demo.app';
    final phone = userModel?.phone ?? '+91 9876543210';
    final deviceId = userModel?.deviceId ?? 'P001';

    return Scaffold(
      backgroundColor: AppTheme.patientBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 32),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF2A0A18), Color(0xFF1A0A0F)],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFF7B1A4A), Color(0xFF2A0A18)],
                      ),
                      boxShadow: AppTheme.pinkGlow,
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'P',
                        style: AppTheme.headline.copyWith(fontSize: 36, color: AppTheme.pinkLight),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(name, style: AppTheme.headline),
                  Text('Patient · $deviceId', style: AppTheme.caption),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _card([
                    _row(Icons.email_outlined, 'Email', email),
                    _divider(),
                    _row(Icons.phone_outlined, 'Phone', phone),
                    _divider(),
                    _row(Icons.devices, 'Device ID', deviceId),
                    _divider(),
                    _row(Icons.calendar_today_outlined, 'Registered',
                        AppHelpers.formatDate(DateTime.now()
                            .subtract(const Duration(days: 14))
                            .millisecondsSinceEpoch)),
                  ]),
                  const SizedBox(height: 20),
                  _card([
                    _row(Icons.person_outline, 'Assigned Doctor', 'Dr. Assigned'),
                    _divider(),
                    _row(Icons.contact_phone_outlined, 'Guardian', '+91 9123456789'),
                  ]),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: demoMode
                        ? () => Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (_) => false)
                        : () async {
                            await context.read<AuthService>().signOut();
                            if (context.mounted) {
                              Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                                  (_) => false);
                            }
                          },
                    child: Container(
                      width: double.infinity, height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.error.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout, color: AppTheme.error, size: 18),
                          const SizedBox(width: 8),
                          Text('Sign Out', style: AppTheme.buttonText.copyWith(color: AppTheme.error)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        decoration: AppTheme.cardDecoration,
        child: Column(children: children),
      );

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.pinkMuted, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppTheme.body.copyWith(color: AppTheme.textSecondary))),
            Text(value, style: AppTheme.body.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _divider() =>
      Divider(color: AppTheme.pinkMuted.withOpacity(0.2), height: 1, indent: 16);
}
