import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/firebase_service.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';
import '../../widgets/affirmation_card.dart';
import '../../widgets/mood_checkin_card.dart';
import 'breathing_exercise_screen.dart';

class MaatricareTab extends StatefulWidget {
  final String patientId;
  final bool demoMode;

  const MaatricareTab({super.key, required this.patientId, this.demoMode = false});

  @override
  State<MaatricareTab> createState() => _MaatricareTabState();
}

class _MaatricareTabState extends State<MaatricareTab> {
  final PageController _affirmCtrl = PageController();
  int _affirmPage = 0;
  final int _dayIndex = DateTime.now().weekday - 1; // 0–6

  @override
  void dispose() {
    _affirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todayAffirmation = AppConstants.affirmations[_dayIndex % AppConstants.affirmations.length];

    return Scaffold(
      backgroundColor: AppTheme.patientBg,
      body: Stack(
        children: [
          // Large ambient pink blob
          Positioned(
            top: -80, left: 0, right: 0,
            child: Center(
              child: Container(
                width: 320, height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    AppTheme.pink.withOpacity(0.10),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          // Mother silhouette subtle
          Positioned(
            bottom: 80, right: -20,
            child: Opacity(
              opacity: 0.05,
              child: Image.asset(
                'assets/images/mother_child_silhouette.png',
                width: 200, height: 240,
                color: AppTheme.pink, colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, __, ___) => const SizedBox(width: 200, height: 240),
              ),
            ),
          ),
          // Content
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MaatriCare', style: AppTheme.headline),
                      Text('Your daily wellness companion', style: AppTheme.caption),
                    ],
                  ),
                ),
              ),
              // Mood check-in
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: MoodCheckinCard(
                    onMoodSelected: (v, label) async {
                      if (!widget.demoMode) {
                        await context.read<FirebaseService>().saveMood(widget.patientId, v, label);
                      }
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Breathing exercise
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BreathingExerciseScreen(
                          patientId: widget.patientId,
                          demoMode: widget.demoMode,
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2A1020), Color(0xFF1A0A18)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.pinkMuted.withOpacity(0.5), width: 1),
                        boxShadow: AppTheme.pinkGlow,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.pink.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.air, color: AppTheme.pink, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Breathing Exercise', style: AppTheme.subhead),
                                Text('4-4-4 breathing • 5 minutes', style: AppTheme.caption),
                                const SizedBox(height: 4),
                                Text('Calms heart rate and reduces anxiety',
                                    style: AppTheme.body.copyWith(fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.pinkMuted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Daily affirmation
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Daily Affirmation', style: AppTheme.subhead),
                          Text('Swipe for more', style: AppTheme.caption),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 160,
                        child: PageView(
                          controller: _affirmCtrl,
                          onPageChanged: (i) => setState(() => _affirmPage = i),
                          children: AppConstants.affirmations
                              .map((text) => AffirmationCard(text: text))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          AppConstants.affirmations.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            width: _affirmPage == i ? 16 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _affirmPage == i ? AppTheme.pink : AppTheme.pinkMuted.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // EPDS result placeholder
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.cardDecoration,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.psychology_outlined, color: AppTheme.success, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('EPDS Score', style: AppTheme.subhead),
                              Text('Last score: 4/30 — Low risk', style: AppTheme.caption),
                              Text('Keep checking in. You are doing great.',
                                  style: AppTheme.body.copyWith(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Peer support placeholder
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppTheme.pinkMuted.withOpacity(0.2), width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.people_outline, color: AppTheme.pinkMuted, size: 28),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Peer Support', style: AppTheme.subhead.copyWith(color: AppTheme.textSecondary)),
                            Text('Coming Soon', style: AppTheme.caption.copyWith(color: AppTheme.gold)),
                            Text('Connect with other mothers', style: AppTheme.body.copyWith(fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
