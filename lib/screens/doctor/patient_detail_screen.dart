import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/patient_model.dart';
import '../../models/vitals_model.dart';
import '../../models/alert_model.dart';
import '../../services/firebase_service.dart';
import '../../utils/theme.dart';
import '../../utils/helpers.dart';
import '../../utils/constants.dart';
import '../../widgets/trend_chart.dart';
import '../../widgets/alert_card.dart';
import '../../widgets/risk_badge.dart';

class PatientDetailScreen extends StatefulWidget {
  final PatientModel patient;
  final bool demoMode;

  const PatientDetailScreen({
    super.key,
    required this.patient,
    this.demoMode = false,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  VitalsModel? _latestVitals;
  List<VitalsHistoryEntry> _history = [];
  List<AlertModel> _alerts = [];
  bool _historyLoading = true;
  Timer? _demoTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    if (widget.demoMode) {
      _latestVitals = DemoData.vitals();
      _history = DemoData.history();
      _historyLoading = false;
      _alerts = [DemoData.pphAlert()..resolved == false ? null : null].whereType<AlertModel>().toList();
      // Simulate PPH after 30s
      _demoTimer = Timer(Duration(seconds: AppConstants.demoAlertDelay), () {
        if (mounted) {
          setState(() {
            _latestVitals = DemoData.vitals(pph: true);
            _alerts = [DemoData.pphAlert()];
          });
        }
      });
    } else {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    final svc = context.read<FirebaseService>();
    final h = await svc.getVitalsHistory(widget.patient.patientId);
    if (mounted) setState(() { _history = h; _historyLoading = false; });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _demoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.read<FirebaseService>();
    final patient = widget.patient;

    Widget buildVitals(VitalsModel? v) {
      if (v == null) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No vital signs yet', style: TextStyle(color: AppTheme.textTertiary))),
        );
      }
      final hrSt = AppHelpers.hrStatus(v.heartRate, v.baselineHR);
      final spo2St = AppHelpers.spo2Status(v.spo2);
      final tempSt = AppHelpers.tempStatus(v.temperature, v.baselineTemp);

      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _vitalCard('Heart Rate', '${v.heartRate.round()}', 'BPM', hrSt, Icons.favorite)),
                const SizedBox(width: 10),
                Expanded(child: _vitalCard('SpO₂', '${v.spo2.round()}', '%', spo2St, Icons.air)),
                const SizedBox(width: 10),
                Expanded(child: _vitalCard('Temp', v.temperature.toStringAsFixed(1), '°C', tempSt, Icons.thermostat)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.success,
                    boxShadow: [BoxShadow(color: AppTheme.success.withOpacity(0.4), blurRadius: 6)],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Live • ${AppHelpers.formatTimestamp(v.timestamp)}',
                  style: AppTheme.caption,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            backgroundColor: AppTheme.bgSecondary,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patient.name, style: AppTheme.subhead),
                Text('${patient.age}y • ${patient.deviceId}', style: AppTheme.caption),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: RiskBadge(level: patient.riskLevel)),
              ),
            ],
          ),

          // Live vitals
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.bgSecondary, AppTheme.bgPrimary],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ),
              ),
              child: widget.demoMode
                  ? buildVitals(_latestVitals)
                  : StreamBuilder<VitalsModel?>(
                      stream: svc.watchLatestVitals(patient.patientId),
                      builder: (ctx, snap) => buildVitals(snap.data),
                    ),
            ),
          ),

          // Trend charts with tabs
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trends (last 24h)', style: AppTheme.subhead),
                  const SizedBox(height: 8),
                  TabBar(
                    controller: _tabCtrl,
                    indicatorColor: AppTheme.pink,
                    labelColor: AppTheme.pinkLight,
                    unselectedLabelColor: AppTheme.textTertiary,
                    tabs: const [Tab(text: 'HR'), Tab(text: 'SpO₂'), Tab(text: 'Temp')],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: _historyLoading
                        ? const Center(child: CircularProgressIndicator(color: AppTheme.pink))
                        : TabBarView(
                            controller: _tabCtrl,
                            children: [
                              TrendChart(history: _history, type: 'hr', baseline: _latestVitals?.baselineHR),
                              TrendChart(history: _history, type: 'spo2'),
                              TrendChart(history: _history, type: 'temp', baseline: _latestVitals?.baselineTemp),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Screening results
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Screening Results', style: AppTheme.subhead),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.5,
                    children: [
                      _screeningCard('GDM Risk', 'Low', AppTheme.success, Icons.bloodtype_outlined),
                      _screeningCard('Thyroid', 'Low', AppTheme.success, Icons.self_improvement),
                      _screeningCard('EPDS Score', '4/30', AppTheme.success, Icons.psychology_outlined),
                      _screeningCard('HRV Status', 'Normal', AppTheme.success, Icons.favorite_border),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Alert history
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Alert History', style: AppTheme.subhead),
                  const SizedBox(height: 12),
                  if (_alerts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: AppTheme.cardDecoration,
                      child: Center(child: Text('No alerts', style: AppTheme.caption)),
                    )
                  else
                    ...(_alerts.map((a) => AlertCard(alert: a))),
                ],
              ),
            ),
          ),

          // Action buttons
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              child: Row(
                children: [
                  Expanded(child: _actionButton('Call Patient', Icons.call, AppTheme.success,
                      () => HapticFeedback.mediumImpact())),
                  const SizedBox(width: 10),
                  Expanded(child: _actionButton('Referral', Icons.assignment, AppTheme.gold,
                      () => HapticFeedback.mediumImpact())),
                  const SizedBox(width: 10),
                  Expanded(child: _actionButton('Discharge', Icons.check_circle_outline, AppTheme.pinkMuted,
                      () => HapticFeedback.mediumImpact())),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vitalCard(String label, String value, String unit, String status, IconData icon) {
    final color = AppHelpers.statusColor(status);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 3),
          top: BorderSide(color: AppTheme.pinkMuted.withOpacity(0.3), width: 1),
          right: BorderSide(color: AppTheme.pinkMuted.withOpacity(0.3), width: 1),
          bottom: BorderSide(color: AppTheme.pinkMuted.withOpacity(0.3), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.playfairDisplay(
            fontSize: 26, fontWeight: FontWeight.w300, color: AppTheme.textPrimary)),
          Text(unit, style: AppTheme.caption),
          Text(label, style: AppTheme.caption.copyWith(fontSize: 9)),
        ],
      ),
    );
  }

  Widget _screeningCard(String title, String result, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.caption),
              Text(result, style: AppTheme.subhead.copyWith(color: color, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label, style: AppTheme.caption.copyWith(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
