import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/firebase_service.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';

class EpdsQuestionnaireScreen extends StatefulWidget {
  final String patientId;
  final bool demoMode;

  const EpdsQuestionnaireScreen({
    super.key,
    required this.patientId,
    this.demoMode = false,
  });

  @override
  State<EpdsQuestionnaireScreen> createState() => _EpdsQuestionnaireScreenState();
}

class _EpdsQuestionnaireScreenState extends State<EpdsQuestionnaireScreen> {
  int _questionIndex = 0;
  final List<int> _responses = [];
  bool _submitted = false;
  int _score = 0;

  void _selectOption(int optionIndex) async {
    setState(() => _responses.add(optionIndex));

    if (_questionIndex < AppConstants.epdsQuestions.length - 1) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) setState(() => _questionIndex++);
    } else {
      // Calculate score — first 2 questions score in reverse (0,1,2,3 → 3,2,1,0)
      int total = 0;
      for (int i = 0; i < _responses.length; i++) {
        if (i == 0 || i == 1) {
          total += (3 - _responses[i]);
        } else {
          total += _responses[i];
        }
      }
      setState(() { _score = total; _submitted = true; });
      if (!widget.demoMode) {
        await context.read<FirebaseService>().saveEpds(
          widget.patientId, total, _responses);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildResult();

    final question = AppConstants.epdsQuestions[_questionIndex];
    final options = AppConstants.epdsOptions[_questionIndex];
    final progress = (_questionIndex + 1) / AppConstants.epdsQuestions.length;

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header + progress
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('EPDS Assessment', style: AppTheme.subhead),
                            Text('Question ${_questionIndex + 1} of ${AppConstants.epdsQuestions.length}',
                                style: AppTheme.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppTheme.surfaceElevated,
                      color: AppTheme.pink,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Padding(
                  key: ValueKey(_questionIndex),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Text('In the past 7 days...', style: AppTheme.caption.copyWith(color: AppTheme.gold)),
                      const SizedBox(height: 12),
                      Text(question, style: AppTheme.subhead.copyWith(height: 1.5, fontSize: 18)),
                      const SizedBox(height: 32),
                      ...options.asMap().entries.map((e) {
                        final score = e.key;
                        final text = e.value;
                        return GestureDetector(
                          onTap: () => _selectOption(score),
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceCard,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppTheme.pinkMuted.withOpacity(0.4), width: 1),
                            ),
                            child: Text(text, style: AppTheme.body.copyWith(color: AppTheme.textPrimary)),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final color = AppConstants.epdsScoreColor(_score);
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: AppTheme.cardDecoration,
            child: Column(
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.15),
                    border: Border.all(color: color.withOpacity(0.5), width: 2),
                  ),
                  child: Center(
                    child: Text('$_score', style: AppTheme.headline.copyWith(color: color)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('EPDS Score', style: AppTheme.subhead),
                const SizedBox(height: 4),
                Text('out of 30', style: AppTheme.caption),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Text(
                    AppConstants.epdsInterpretation(_score),
                    style: AppTheme.body.copyWith(color: color),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity, height: 52,
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
      ),
    );
  }
}

// Extension to use epdsScoreColor in constants
extension on AppConstants {
  static Color epdsScoreColor(int score) {
    if (score <= 9) return AppTheme.success;
    if (score <= 12) return AppTheme.warning;
    return AppTheme.error;
  }
}
