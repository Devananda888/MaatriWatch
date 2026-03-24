import 'package:flutter/material.dart';
import '../utils/theme.dart';

class StatusBanner extends StatefulWidget {
  final String status; // 'normal' | 'warning' | 'critical'
  final String message;

  const StatusBanner({super.key, required this.status, required this.message});

  @override
  State<StatusBanner> createState() => _StatusBannerState();
}

class _StatusBannerState extends State<StatusBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.status == 'critical') _glow.repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.status) {
      case 'critical': return AppTheme.error;
      case 'warning':  return AppTheme.warning;
      default:         return AppTheme.success;
    }
  }

  IconData get _icon {
    switch (widget.status) {
      case 'critical': return Icons.warning_rounded;
      case 'warning':  return Icons.info_outline;
      default:         return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, __) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: color, width: 4),
            bottom: BorderSide(color: color.withOpacity(0.2), width: 1),
          ),
          boxShadow: widget.status == 'critical'
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.10 + 0.20 * _glow.value),
                    blurRadius: 16,
                    spreadRadius: 2 * _glow.value,
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(_icon, color: color, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.message,
                style: AppTheme.bodySmall.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
