import 'package:flutter/material.dart';
import '../utils/theme.dart';

class PinkGlowOrb extends StatelessWidget {
  final double width;
  final double height;
  final double opacity;

  const PinkGlowOrb({
    super.key,
    this.width = 200,
    this.height = 200,
    this.opacity = 0.12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppTheme.pink.withOpacity(opacity),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
