import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/alert_model.dart';
import '../../services/firebase_service.dart';
import '../../utils/theme.dart';
import '../../widgets/alert_card.dart';

class AlertsTab extends StatelessWidget {
  final String doctorId;
  final bool demoMode;

  const AlertsTab({super.key, required this.doctorId, this.demoMode = false});

  @override
  Widget build(BuildContext context) {
    final svc = context.read<FirebaseService>();

    final demoAlerts = [
      DemoData.pphAlert(),
      AlertModel(
        alertId: 'demo_2',
        patientId: 'demo_anjali',
        type: 'PREECLAMPSIA_RISK',
        heartRate: 96,
        spo2: 93,
        temperature: 37.8,
        timestamp: DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
        resolved: false,
      ),
    ];

    Widget buildList(List<AlertModel> alerts) {
      final unresolved = alerts.where((a) => !a.resolved).toList();
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Active Alerts', style: AppTheme.headline),
                  const SizedBox(height: 4),
                  Text(
                    unresolved.isEmpty
                        ? 'All patients stable'
                        : '${unresolved.length} alert${unresolved.length > 1 ? 's' : ''} require attention',
                    style: AppTheme.caption.copyWith(
                      color: unresolved.isEmpty ? AppTheme.success : AppTheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (unresolved.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, color: AppTheme.success.withOpacity(0.5), size: 64),
                    const SizedBox(height: 16),
                    Text('No active alerts', style: AppTheme.subhead),
                    const SizedBox(height: 8),
                    Text('All patients stable', style: AppTheme.caption),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final alert = unresolved[i];
                    return AlertCard(
                      alert: alert,
                      patientName: alert.patientId == 'demo_priya'
                          ? 'Priya Sharma'
                          : alert.patientId == 'demo_anjali'
                              ? 'Anjali Singh'
                              : 'Patient',
                      onMarkResolved: demoMode
                          ? null
                          : () => svc.resolveAlert(alert.patientId, alert.alertId),
                    );
                  },
                  childCount: unresolved.length,
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.doctorBg,
      body: demoMode
          ? buildList(demoAlerts)
          : StreamBuilder<List<AlertModel>>(
              stream: svc.watchAllDoctorAlerts([doctorId]),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppTheme.pink));
                }
                return buildList(snap.data ?? []);
              },
            ),
    );
  }
}
