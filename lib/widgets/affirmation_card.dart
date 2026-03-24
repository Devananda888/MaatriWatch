import 'package:flutter/material.dart';
import '../utils/theme.dart';

class AffirmationCard extends StatelessWidget {
  final String text;

  const AffirmationCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1020), Color(0xFF1A0A18)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: const Border(
          left: BorderSide(color: AppTheme.pink, width: 3),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.pink.withOpacity(0.12),
            blurRadius: 20,
            spreadRadius: -4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote, color: AppTheme.pink.withOpacity(0.6), size: 28),
          const SizedBox(height: 8),
          Text(text, style: AppTheme.affirmation),
        ],
      ),
    );
  }
}
