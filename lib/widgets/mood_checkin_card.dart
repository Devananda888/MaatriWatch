import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/theme.dart';

class MoodCheckinCard extends StatefulWidget {
  final Function(int mood, String label) onMoodSelected;

  const MoodCheckinCard({super.key, required this.onMoodSelected});

  @override
  State<MoodCheckinCard> createState() => _MoodCheckinCardState();
}

class _MoodCheckinCardState extends State<MoodCheckinCard> {
  int? _selectedMood;

  static const List<Map<String, dynamic>> _moods = [
    {'value': 1, 'emoji': '😊', 'label': 'Good'},
    {'value': 2, 'emoji': '😐', 'label': 'Okay'},
    {'value': 3, 'emoji': '😔', 'label': 'Not well'},
    {'value': 4, 'emoji': '😢', 'label': 'Very low'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How are you feeling today?', style: AppTheme.subhead),
          const SizedBox(height: 4),
          Text('Tap to log your daily mood', style: AppTheme.caption),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _moods.map((mood) {
              final isSelected = _selectedMood == mood['value'];
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedMood = mood['value'] as int);
                  widget.onMoodSelected(mood['value'] as int, mood['label'] as String);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.pink
                          : AppTheme.pinkMuted.withOpacity(0.3),
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppTheme.pink.withOpacity(0.3),
                              blurRadius: 16,
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(mood['emoji'] as String,
                          style: const TextStyle(fontSize: 26)),
                      const SizedBox(height: 4),
                      Text(
                        mood['label'] as String,
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          color: isSelected
                              ? AppTheme.pinkLight
                              : AppTheme.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_selectedMood != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: AppTheme.success, size: 16),
                const SizedBox(width: 6),
                Text('Mood logged', style: AppTheme.caption.copyWith(color: AppTheme.success)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
