import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../patient/patient_home.dart';

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('MaatriWatch')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(MaatriTokens.space16),
                children: [
                  Text('Choose your profile',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: MaatriTokens.space8),
                  Text(
                      'Select a profile to access the right MaatriWatch workspace.',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: MaatriTokens.space24),
                  _ProfileCard(
                    icon: Icons.person_outline_rounded,
                    title: 'User',
                    subtitle: 'Care plan, appointments and family support',
                    onTap: () => _open(context, const UserHome()),
                  ),
                  const SizedBox(height: MaatriTokens.space12),
                  _ProfileCard(
                    icon: Icons.favorite_outline_rounded,
                    title: 'Patient',
                    subtitle: 'Wearable readings, SOS and wellbeing check-in',
                    onTap: () => _open(context, const PatientHome()),
                  ),
                  const SizedBox(height: MaatriTokens.space12),
                  _ProfileCard(
                    icon: Icons.medical_services_outlined,
                    title: 'Doctor',
                    subtitle: 'Patient round, risk alerts and clinical actions',
                    onTap: () => _open(context, const DoctorHome()),
                  ),
                  const SizedBox(height: MaatriTokens.space12),
                  _ProfileCard(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Admin',
                    subtitle: 'Hospital activity, devices and care-team access',
                    onTap: () => _open(context, const AdminHome()),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

class UserHome extends StatelessWidget {
  const UserHome({super.key});

  @override
  Widget build(BuildContext context) => _ProfileScaffold(
        title: 'Care companion',
        child: ListView(
          padding: const EdgeInsets.all(MaatriTokens.space16),
          children: [
            Text('Hello, Anjali',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: MaatriTokens.space8),
            const Text(
                'Stay connected to your postpartum care plan and support network.'),
            const SizedBox(height: MaatriTokens.space24),
            const _InfoCard(
                icon: Icons.calendar_month_outlined,
                title: 'Next follow-up',
                value: '18 Aug, 10:30 AM',
                caption: 'MACE Women’s Health Clinic'),
            const SizedBox(height: MaatriTokens.space12),
            const _InfoCard(
                icon: Icons.groups_outlined,
                title: 'Support contact',
                value: 'Asha, ASHA worker',
                caption: 'Available today until 6:00 PM'),
            const SizedBox(height: MaatriTokens.space12),
            const _InfoCard(
                icon: Icons.check_circle_outline_rounded,
                title: 'Care plan',
                value: '3 of 4 tasks complete',
                caption: 'Hydration, rest and check-in are on track'),
          ],
        ),
      );
}

class DoctorHome extends StatelessWidget {
  const DoctorHome({super.key});

  @override
  Widget build(BuildContext context) => _ProfileScaffold(
        title: 'Doctor workspace',
        child: ListView(
          padding: const EdgeInsets.all(MaatriTokens.space16),
          children: [
            Text('Morning round',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: MaatriTokens.space8),
            const Text('8 mothers are under active observation today.'),
            const SizedBox(height: MaatriTokens.space24),
            const _InfoCard(
                icon: Icons.notifications_active_outlined,
                title: 'Priority review',
                value: '2 alerts need attention',
                caption: 'Review high-risk readings first',
                color: MaatriTokens.critical),
            const SizedBox(height: MaatriTokens.space12),
            const _PatientStatus(
                name: 'Asha Nair',
                detail: 'Heart rate 82 bpm • SpO₂ 98%',
                status: 'Stable',
                color: MaatriTokens.success),
            const SizedBox(height: MaatriTokens.space12),
            const _PatientStatus(
                name: 'Meera Das',
                detail: 'Heart rate 106 bpm • Temperature 38.1°C',
                status: 'Review',
                color: MaatriTokens.warning),
            const SizedBox(height: MaatriTokens.space12),
            const _PatientStatus(
                name: 'Fathima K.',
                detail: 'Fall event detected • 4 minutes ago',
                status: 'Urgent',
                color: MaatriTokens.critical),
          ],
        ),
      );
}

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) => _ProfileScaffold(
        title: 'Hospital administration',
        child: ListView(
          padding: const EdgeInsets.all(MaatriTokens.space16),
          children: [
            Text('MACE Women’s Health Clinic',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: MaatriTokens.space8),
            const Text('Today’s care operations at a glance.'),
            const SizedBox(height: MaatriTokens.space24),
            const _InfoCard(
                icon: Icons.people_outline,
                title: 'Active patients',
                value: '8',
                caption: 'All assigned to a care team'),
            const SizedBox(height: MaatriTokens.space12),
            const _InfoCard(
                icon: Icons.watch_outlined,
                title: 'Devices assigned',
                value: '8 of 10',
                caption: '2 devices available for issue'),
            const SizedBox(height: MaatriTokens.space12),
            const _InfoCard(
                icon: Icons.badge_outlined,
                title: 'Care-team access',
                value: '6 active clinicians',
                caption: 'No pending access requests'),
          ],
        ),
      );
}

class _ProfileScaffold extends StatelessWidget {
  const _ProfileScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: 'Change profile',
              icon: const Icon(Icons.switch_account_outlined),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: SafeArea(child: child),
      );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

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
            padding: const EdgeInsets.all(MaatriTokens.space16),
            child: Row(
              children: [
                Icon(icon, size: 32, color: MaatriTokens.primary),
                const SizedBox(width: MaatriTokens.space16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: MaatriTokens.space4),
                      Text(subtitle)
                    ])),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 18, color: MaatriTokens.textMuted),
              ],
            ),
          ),
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon,
      required this.title,
      required this.value,
      required this.caption,
      this.color = MaatriTokens.primary});

  final IconData icon;
  final String title;
  final String value;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(MaatriTokens.space16),
          leading: Icon(icon, color: color, size: 30),
          title: Text(title),
          subtitle: Text(caption),
          trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleMedium)),
        ),
      );
}

class _PatientStatus extends StatelessWidget {
  const _PatientStatus(
      {required this.name,
      required this.detail,
      required this.status,
      required this.color});

  final String name;
  final String detail;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(MaatriTokens.space16),
          title: Text(name),
          subtitle: Text(detail),
          trailing: Text(status,
              style: MaatriTokens.type(
                  size: MaatriTokens.type14,
                  weight: FontWeight.w800,
                  color: color)),
        ),
      );
}
