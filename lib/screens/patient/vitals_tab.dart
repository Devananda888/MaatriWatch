import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/vitals_model.dart';
import '../../services/firebase_service.dart';
import '../../utils/theme.dart';
import '../../utils/helpers.dart';
import '../../utils/constants.dart';
import '../../widgets/status_banner.dart';
import '../../widgets/vitals_card.dart';
import '../../widgets/trend_chart.dart';

class VitalsTab extends StatefulWidget {
  final String patientId;
  final bool demoMode;

  const VitalsTab({super.key, required this.patientId, this.demoMode = false});

  @override
  State<VitalsTab> createState() => _VitalsTabState();
}

class _VitalsTabState extends State<VitalsTab> {
  bool _isHoldingSOS = false;
  double _sosProgress = 0.0;
  Timer? _sosTimer;
  VitalsModel? _latestVitals;
  List<VitalsHistoryEntry> _history = [];
  Timer? _demoTimer;

  @override
  void initState() {
    super.initState();
    if (widget.demoMode) {
      _latestVitals = DemoData.vitals();
      _history = DemoData.history();
      _demoTimer = Timer(Duration(seconds: AppConstants.demoAlertDelay), () {
        if (mounted) setState(() => _latestVitals = DemoData.vitals(pph: true));
      });
    } else {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    final svc = context.read<FirebaseService>();
    final h = await svc.getVitalsHistory(widget.patientId);
    if (mounted) setState(() => _history = h);
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    _demoTimer?.cancel();
    super.dispose();
  }

  void _startSOSCountdown() {
    setState(() { _isHoldingSOS = true; _sosProgress = 0.0; });
    HapticFeedback.heavyImpact();
    int ticks = 0;
    _sosTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      ticks++;
      final prog = ticks / (AppConstants.sosHoldDuration * 1000 / 50);
      if (!mounted) { t.cancel(); return; }
      setState(() => _sosProgress = prog);
      if (prog >= 1.0) {
        t.cancel();
        _fireSOS();
      }
    });
  }

  void _cancelSOS() {
    _sosTimer?.cancel();
    if (mounted) setState(() { _isHoldingSOS = false; _sosProgress = 0.0; });
  }

  Future<void> _fireSOS() async {
    HapticFeedback.heavyImpact();
    setState(() { _isHoldingSOS = false; _sosProgress = 0.0; });
    if (!widget.demoMode && _latestVitals != null) {
      await context.read<FirebaseService>().sendSosAlert(widget.patientId, _latestVitals!);
    }
    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surfaceElevated,
          title: Text('SOS Alert Sent', style: AppTheme.subhead.copyWith(color: AppTheme.error)),
          content: Text('Your doctor and guardian have been notified. Help is on the way. Stay calm.', style: AppTheme.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK', style: TextStyle(color: AppTheme.pinkLight)),
            ),
          ],
        ),
      );
    }
  }

  String _statusFromVitals(VitalsModel? v) {
    if (v == null) return AppConstants.riskNormal;
    return AppHelpers.overallPatientRisk(
        v.heartRate, v.spo2, v.temperature, v.baselineHR, v.baselineTemp);
  }

  String _bannerMessage(String status) {
    switch (status) {
      case AppConstants.riskCritical:
        return 'ALERT SENT — Help is on the way. Stay calm.';
      case AppConstants.riskWarning:
        return 'Attention — unusual readings detected.';
      default:
        return 'You are being monitored. All vitals normal. 💚';
    }
  }

  Widget _buildContent(VitalsModel? v) {
    final status = _statusFromVitals(v);
    final hrSt = v != null ? AppHelpers.hrStatus(v.heartRate, v.baselineHR) : 'normal';
    final spo2St = v != null ? AppHelpers.spo2Status(v.spo2) : 'normal';
    final tempSt = v != null ? AppHelpers.tempStatus(v.temperature, v.baselineTemp) : 'normal';

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 56),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('My Vitals', style: AppTheme.headline),
                const Spacer(),
                if (v != null)
                  Text(
                    AppHelpers.formatTimestamp(v.timestamp),
                    style: AppTheme.caption,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Status banner
          StatusBanner(status: status, message: _bannerMessage(status)),

          // Live vitals cards
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: VitalsCard(
                      label: 'Heartbeat',
                      value: v != null ? '${v.heartRate.round()}' : '--',
                      unit: 'BPM',
                      status: hrSt,
                      icon: Icons.favorite,
                      normalRange: AppConstants.hrNormalRange,
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: VitalsCard(
                      label: 'Oxygen Level',
                      value: v != null ? '${v.spo2.round()}' : '--',
                      unit: '%',
                      status: spo2St,
                      icon: Icons.air,
                      normalRange: AppConstants.spo2NormalRange,
                    )),
                  ],
                ),
                const SizedBox(height: 10),
                VitalsCard(
                  label: 'Body Temperature',
                  value: v != null ? v.temperature.toStringAsFixed(1) : '--',
                  unit: '°C',
                  status: tempSt,
                  icon: Icons.thermostat,
                  normalRange: AppConstants.tempNormalRange,
                ),
              ],
            ),
          ),

          // HR Chart
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your heartbeat today', style: AppTheme.subhead),
                const SizedBox(height: 8),
                TrendChart(
                  history: _history,
                  type: 'hr',
                  baseline: v?.baselineHR,
                ),
              ],
            ),
          ),

          // Emergency SOS
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              children: [
                Text('Emergency', style: AppTheme.subhead),
                const SizedBox(height: 4),
                Text('Hold 3 seconds to send SOS alert', style: AppTheme.caption),
                const SizedBox(height: 20),
                GestureDetector(
                  onLongPressStart: (_) => _startSOSCountdown(),
                  onLongPressEnd: (_) => _cancelSOS(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [AppTheme.pink, AppTheme.pinkMuted],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.pink.withOpacity(_isHoldingSOS ? 0.65 : 0.28),
                          blurRadius: _isHoldingSOS ? 50 : 24,
                          spreadRadius: _isHoldingSOS ? 10 : 0,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_isHoldingSOS)
                          SizedBox(
                            width: 160, height: 160,
                            child: CircularProgressIndicator(
                              value: _sosProgress,
                              color: Colors.white.withOpacity(0.5),
                              strokeWidth: 4,
                            ),
                          ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.warning_rounded, color: Colors.white, size: 40),
                            const SizedBox(height: 6),
                            Text('EMERGENCY', style: GoogleFonts.dmSans(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: Colors.white, letterSpacing: 1.8,
                            )),
                            Text('Hold 3 seconds', style: GoogleFonts.dmSans(
                              fontSize: 10, color: Colors.white70,
                            )),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.read<FirebaseService>();
    return Scaffold(
      backgroundColor: AppTheme.patientBg,
      body: widget.demoMode
          ? _buildContent(_latestVitals)
          : StreamBuilder<VitalsModel?>(
              stream: svc.watchLatestVitals(widget.patientId),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.pink));
                }
                return _buildContent(snap.data);
              },
            ),
    );
  }
}
