import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// 3-layer background: RadialGradient + pink glow orb + mother/child silhouette.
class MotherSilhouetteBg extends StatelessWidget {
  final Widget child;
  final bool showOrb;

  const MotherSilhouetteBg({
    super.key,
    required this.child,
    this.showOrb = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.3, -0.6),
          radius: 1.4,
          colors: [Color(0xFF2A0A18), Color(0xFF0D0D0D)],
        ),
      ),
      child: Stack(
        children: [
          // Layer 3 — ambient pink glow orb (top-center)
          if (showOrb)
            Positioned(
              top: -60,
              left: MediaQuery.of(context).size.width * 0.3,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.pink.withOpacity(0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

          // Layer 2 — Mother & child silhouette (bottom-right, barely visible)
          Positioned(
            bottom: -20,
            right: -30,
            child: Opacity(
              opacity: 0.06,
              child: Image.asset(
                'assets/images/mother_child_silhouette.png',
                width: 280,
                height: 320,
                fit: BoxFit.contain,
                color: AppTheme.pink,
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, __, ___) => const SizedBox(width: 280, height: 320),
              ),
            ),
          ),

          // Content
          child,
        ],
      ),
    );
  }
}
