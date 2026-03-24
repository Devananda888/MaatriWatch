import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/theme.dart';
import '../../widgets/mother_silhouette_bg.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _orbCtrl;
  late AnimationController _logoCtrl;
  late AnimationController _subtitleCtrl;
  late AnimationController _teamCtrl;

  late Animation<double> _orbScale;
  late Animation<double> _logoOpacity;
  late Animation<Offset> _logoSlide;
  late Animation<double> _subtitleOpacity;
  late Animation<double> _teamOpacity;

  @override
  void initState() {
    super.initState();

    _orbCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _subtitleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _teamCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

    _orbScale = Tween<double>(begin: 0.0, end: 1.2)
        .animate(CurvedAnimation(parent: _orbCtrl, curve: Curves.easeOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut));
    _logoSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut));
    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _subtitleCtrl, curve: Curves.easeOut));
    _teamOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _teamCtrl, curve: Curves.easeOut));

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _orbCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _subtitleCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _teamCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  void dispose() {
    _orbCtrl.dispose();
    _logoCtrl.dispose();
    _subtitleCtrl.dispose();
    _teamCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: MotherSilhouetteBg(
        showOrb: false,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pink glow orb
            AnimatedBuilder(
              animation: _orbScale,
              builder: (_, __) => Transform.scale(
                scale: _orbScale.value,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.pink.withOpacity(0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Center text content
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App name
                FadeTransition(
                  opacity: _logoOpacity,
                  child: SlideTransition(
                    position: _logoSlide,
                    child: Text(
                      'MaatriWatch',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 40,
                        fontWeight: FontWeight.w300,
                        color: AppTheme.textPrimary,
                        letterSpacing: 3.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Hindi subtitle
                FadeTransition(
                  opacity: _subtitleOpacity,
                  child: Text(
                    'माँ की निगरानी, पल पल',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Sub-subtitle
                FadeTransition(
                  opacity: _subtitleOpacity,
                  child: Text(
                    'Maternal Health Monitoring',
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textTertiary,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),

            // Team name at bottom
            Positioned(
              bottom: 48,
              child: FadeTransition(
                opacity: _teamOpacity,
                child: Text(
                  'Team CodeBlooded',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppTheme.gold,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
