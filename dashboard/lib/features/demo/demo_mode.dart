import 'package:flutter/material.dart';
import 'package:maatriwatch_patient_app/core/design_tokens.dart';
import 'package:maatriwatch_patient_app/features/patient/patient_home.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../dashboard/dashboard_page.dart';

class DemoRolePicker extends StatelessWidget {
  const DemoRolePicker({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(MaatriTokens.space24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.favorite_rounded, color: MaatriTokens.primary, size: 52),
                  const SizedBox(height: MaatriTokens.space16),
                  Text('MaatriWatch demo', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: MaatriTokens.space8),
                  Text(
                    'Choose a prototype role to begin. No password or OTP is needed for this hackathon demo.',
                    textAlign: TextAlign.center,
                    style: MaatriTokens.type(size: MaatriTokens.type16, color: MaatriTokens.textMuted),
                  ),
                  const SizedBox(height: MaatriTokens.space32),
                  _RoleButton(
                    icon: Icons.medical_services_outlined,
                    title: 'Doctor',
                    subtitle: 'Review patients, trends, alerts, and notes',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _DemoClinicianGate())),
                  ),
                  const SizedBox(height: MaatriTokens.space12),
                  _RoleButton(
                    icon: Icons.favorite_outline_rounded,
                    title: 'Patient',
                    subtitle: 'View simple vitals, use SOS, and complete a check-in',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PatientHome())),
                  ),
                  const SizedBox(height: MaatriTokens.space12),
                  _RoleButton(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Hospital Admin',
                    subtitle: 'See a simple hospital and device overview',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _DemoAdminHome())),
                  ),
                  const SizedBox(height: MaatriTokens.space24),
                  Text(
                    'Demo mode is local to this prototype. Real Firebase Auth remains available when DEMO_MODE is disabled.',
                    textAlign: TextAlign.center,
                    style: MaatriTokens.type(size: MaatriTokens.type12, color: MaatriTokens.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(MaatriTokens.space24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(MaatriTokens.space12),
                  decoration: BoxDecoration(
                    color: MaatriTokens.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(MaatriTokens.radius12),
                  ),
                  child: Icon(icon, color: MaatriTokens.primary, size: 32),
                ),
                const SizedBox(width: MaatriTokens.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: MaatriTokens.space4),
                      Text(subtitle),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: MaatriTokens.textMuted),
              ],
            ),
          ),
        ),
      );
}

class _DemoClinicianGate extends StatefulWidget {
  const _DemoClinicianGate();

  @override
  State<_DemoClinicianGate> createState() => _DemoClinicianGateState();
}

class _DemoClinicianGateState extends State<_DemoClinicianGate> {
  final _api = ApiClient(demoRole: 'clinician');
  late Future<List<HospitalMembership>> _memberships;

  @override
  void initState() {
    super.initState();
    _memberships = _load();
  }

  Future<List<HospitalMembership>> _load() async {
    final payload = await _api.me();
    return (payload['hospital_memberships'] as List<dynamic>? ?? const [])
        .map((item) => HospitalMembership.fromJson(asMap(item)))
        .where((item) => item.role == 'clinician')
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<HospitalMembership>>(
        future: _memberships,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return Scaffold(
              appBar: AppBar(title: const Text('Doctor demo')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(MaatriTokens.space24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.storage_outlined, color: MaatriTokens.warning, size: 44),
                      const SizedBox(height: MaatriTokens.space16),
                      const Text('Demo data is not available. Follow the seed step in the root README, then retry.'),
                      const SizedBox(height: MaatriTokens.space16),
                      OutlinedButton(onPressed: () => setState(() => _memberships = _load()), child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            );
          }
          return DashboardPage(
            api: _api,
            memberships: snapshot.data!,
            demoMode: true,
            onSignOut: () => Navigator.of(context).pop(),
          );
        },
      );
}

class _DemoAdminHome extends StatelessWidget {
  const _DemoAdminHome();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Hospital overview')),
        body: Padding(
          padding: const EdgeInsets.all(MaatriTokens.space16),
          child: ListView(
            children: [
              Text('Demo hospital overview', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: MaatriTokens.space16),
              const _AdminMetric(label: 'Active patients', value: '8', icon: Icons.people_outline),
              const SizedBox(height: MaatriTokens.space12),
              const _AdminMetric(label: 'Devices assigned', value: '8', icon: Icons.watch_outlined),
              const SizedBox(height: MaatriTokens.space12),
              const _AdminMetric(label: 'Alerts needing review', value: '2', icon: Icons.notifications_active_outlined),
              const SizedBox(height: MaatriTokens.space24),
              const Text('This prototype view is intentionally static. Account and device management are on the roadmap.'),
            ],
          ),
        ),
      );
}

class _AdminMetric extends StatelessWidget {
  const _AdminMetric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon, color: MaatriTokens.primary),
          title: Text(label),
          trailing: Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ),
      );
}
