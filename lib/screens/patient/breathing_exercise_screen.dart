import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/firebase_service.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';

class BreathingExerciseScreen extends StatefulWidget {
  final String patientId;
  final bool demoMode;

  const BreathingExerciseScreen({
    super.key,
    required this.patientId,
    this.demoMode = false,
  });

  @override
  State<BreathingExerciseScreen> createState() => _BreathingExerciseScreenState();
}

class _BreathingExerciseScreenState extends State<BreathingExerciseScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _breathCtrl;
  late Animation<double> _radius;
  int _phaseIndex = 0;
  int _totalSeconds = 0;
  Timer? _cycleTimer;
  Timer? _totalTimer;
  final int _sessionDuration = 300; // 5 minutes
  double _hrBefore = 82;
  double _hrAfter = 72;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _radius = Tween<double>(begin: 120, end: 220).animate(
      CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut),
    );
    _startCycle();
    _totalTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _totalSeconds++);
      if (_totalSeconds >= _sessionDuration) _endSession();
    });
  }

  void _startCycle() {
    _runPhase();
  }

  Future<void> _runPhase() async {
    while (mounted && !_finished) {
      final phase = AppConstants.breathPhases[_phaseIndex];
      final duration = phase['duration'] as int;
      final expand = phase['expand'] as bool;

      if (expand) {
        _breathCtrl.forward();
      } else if (!expand && _phaseIndex == 2) {
        _breathCtrl.reverse();
      }

      await Future.delayed(Duration(seconds: duration));
      if (!mounted) return;
      setState(() => _phaseIndex = (_phaseIndex + 1) % AppConstants.breathPhases.length);
    }
  }

  Future<void> _endSession() async {
    _breathCtrl.stop();
    _cycleTimer?.cancel();
    _totalTimer?.cancel();
    if (!mounted) return;
    setState(() => _finished = true);

    if (!widget.demoMode) {
      await context.read<FirebaseService>().saveTherapySession(
        patientId: widget.patientId,
        type: 'breathing',
        duration: _totalSeconds,
        hrBefore: _hrBefore,
        hrAfter: _hrAfter,
      );
    }
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    _cycleTimer?.cancel();
    _totalTimer?.cancel();
    super.dispose();
  }

  String get _timeLeft {
    final remaining = _sessionDuration - _totalSeconds;
    final m = remaining ~/ 60;
    final s = remaining % 60;
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final phase = AppConstants.breathPhases[_phaseIndex];
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: Stack(
        children: [
          // Mother silhouette (0.04 opacity — most emotionally resonant)
          Positioned(
            bottom: 0, right: 0,
            child: Opacity(
              opacity: 0.04,
              child: Image.asset(
                'assets/images/mother_child_silhouette.png',
                width: 320, height: 380,
                color: AppTheme.pink, colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, __, ___) => const SizedBox(width: 320, height: 380),
              ),
            ),
          ),

          // Back button
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new, size: 16, color: AppTheme.textPrimary),
                  ),
                ),
              ),
            ),
          ),

          // Live HR (top-right)
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, color: AppTheme.pink, size: 14),
                    const SizedBox(width: 4),
                    Text('$_hrAfter BPM', style: AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ),
          ),

          // Timer
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(_timeLeft, style: AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
              ),
            ),
          ),

          // Breathing circle
          if (!_finished)
            Center(
              child: AnimatedBuilder(
                animation: _breathCtrl,
                builder: (_, __) {
                  final r = _radius.value;
                  return Container(
                    width: r,
                    height: r,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        AppTheme.pink.withOpacity(0.30),
                        AppTheme.pink.withOpacity(0.05),
                        Colors.transparent,
                      ]),
                      border: Border.all(
                        color: AppTheme.pink.withOpacity(0.6), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.pink.withOpacity(0.25),
                          blurRadius: 40, spreadRadius: 8,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          // Phase label
          if (!_finished)
            Positioned(
              bottom: 180, left: 0, right: 0,
              child: Text(
                phase['label'] as String,
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 28, fontWeight: FontWeight.w300,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),

          // Finished state
          if (_finished)
            Center(
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(28),
                decoration: AppTheme.cardDecoration,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: AppTheme.success, size: 48),
                    const SizedBox(height: 16),
                    Text('Session Complete', style: AppTheme.headline),
                    const SizedBox(height: 8),
                    Text('Great work! Your heart rate responded well to the exercise.',
                        style: AppTheme.body, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _hrStat('Before', _hrBefore),
                        const Icon(Icons.arrow_forward, color: AppTheme.pinkMuted),
                        _hrStat('After', _hrAfter),
                      ],
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: double.infinity, height: 48,
                        decoration: BoxDecoration(
                          gradient: AppTheme.pinkGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(child: Text('Done', style: AppTheme.buttonText)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hrStat(String label, double value) {
    return Column(
      children: [
        Text('$value', style: AppTheme.subhead.copyWith(color: AppTheme.pink)),
        Text('$label BPM', style: AppTheme.caption),
      ],
    );
  }
}
