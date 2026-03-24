import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';
import 'epds_questionnaire_screen.dart';

class ScreeningTab extends StatelessWidget {
  final String patientId;
  final bool demoMode;

  const ScreeningTab({super.key, required this.patientId, this.demoMode = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.patientBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Screening', style: AppTheme.headline),
                  Text('Your health check results', style: AppTheme.caption),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _screeningCard(
                  context,
                  icon: Icons.bloodtype_outlined,
                  title: 'Gestational Diabetes (GDM)',
                  result: 'Low Risk',
                  color: AppTheme.success,
                  detail: 'Based on your questionnaire responses, you have a low risk of GDM.',
                  onAction: null,
                  actionLabel: null,
                ),
                const SizedBox(height: 14),
                _screeningCard(
                  context,
                  icon: Icons.self_improvement,
                  title: 'Thyroid Health',
                  result: 'Low Risk',
                  color: AppTheme.success,
                  detail: 'Your thyroid screening indicators appear normal.',
                  onAction: null,
                  actionLabel: null,
                ),
                const SizedBox(height: 14),
                _screeningCard(
                  context,
                  icon: Icons.psychology_outlined,
                  title: 'Postpartum Depression (EPDS)',
                  result: 'Score: 4/30',
                  color: AppTheme.success,
                  detail: 'Low likelihood of depression. Keep checking in with yourself.',
                  onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EpdsQuestionnaireScreen(
                          patientId: patientId, demoMode: demoMode),
                    ),
                  ),
                  actionLabel: 'Take Assessment',
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _screeningCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String result,
    required Color color,
    required String detail,
    required VoidCallback? onAction,
    required String? actionLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.subhead.copyWith(fontSize: 15)),
                    Text(result,
                        style: AppTheme.body.copyWith(color: color, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(detail, style: AppTheme.bodySmall),
          if (onAction != null) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onAction,
              child: Container(
                width: double.infinity,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppTheme.pinkGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(actionLabel!, style: AppTheme.buttonText.copyWith(fontSize: 14)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
