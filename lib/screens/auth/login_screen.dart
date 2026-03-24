import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';
import '../../widgets/mother_silhouette_bg.dart';
import '../doctor/doctor_dashboard.dart';
import '../patient/patient_dashboard.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  int _logoTapCount = 0;
  bool _demoMode = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onLogoTap() {
    setState(() {
      _logoTapCount++;
      if (_logoTapCount >= 5) {
        _demoMode = true;
        _logoTapCount = 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.surfaceElevated,
            content: Text(
              '🎭 Demo mode activated — Priya Sharma (P001)',
              style: AppTheme.body.copyWith(color: AppTheme.pinkLight),
            ),
          ),
        );
      }
    });
  }

  Future<void> _signIn() async {
    if (_demoMode) {
      _navigateToDemoDoctor();
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() { _loading = true; _error = null; });
    try {
      final auth = context.read<AuthService>();
      final user = await auth.signIn(_emailCtrl.text, _passwordCtrl.text);
      if (!mounted) return;

      if (user.role == AppConstants.roleDoctor) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DoctorDashboard(userModel: user)));
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => PatientDashboard(userModel: user)));
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _navigateToDemoDoctor() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DoctorDashboard(demoMode: true)));
  }

  Future<void> _forgotPassword() async {
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter your email above first.');
      return;
    }
    try {
      await context.read<AuthService>().sendPasswordReset(_emailCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.surfaceElevated,
          content: Text('Password reset email sent.',
              style: AppTheme.body.copyWith(color: AppTheme.success)),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: MotherSilhouetteBg(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppTheme.pinkMuted.withOpacity(0.4), width: 1),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo / app name (5× tap = demo mode)
                      Center(
                        child: GestureDetector(
                          onTap: _onLogoTap,
                          child: Column(
                            children: [
                              Text('MaatriWatch',
                                  style: GoogleFonts.playfairDisplay(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w300,
                                    color: AppTheme.textPrimary,
                                    letterSpacing: 1.0,
                                  )),
                              const SizedBox(height: 4),
                              Text('Maternal Health Monitoring',
                                  style: AppTheme.caption.copyWith(
                                      color: AppTheme.textSecondary)),
                              if (_demoMode)
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.gold.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: AppTheme.gold.withOpacity(0.5)),
                                  ),
                                  child: Text('DEMO MODE',
                                      style: AppTheme.caption.copyWith(
                                          color: AppTheme.gold,
                                          letterSpacing: 1.5)),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Divider
                      Divider(color: AppTheme.pinkMuted.withOpacity(0.5), height: 1),
                      const SizedBox(height: 24),

                      // Email
                      Text('Email', style: AppTheme.label),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailCtrl,
                        style: AppTheme.body.copyWith(color: AppTheme.textPrimary),
                        keyboardType: TextInputType.emailAddress,
                        decoration: AppTheme.inputDecoration(
                            'your@email.com', icon: Icons.email_outlined),
                        validator: (v) =>
                            v != null && v.contains('@') ? null : 'Enter valid email',
                      ),
                      const SizedBox(height: 16),

                      // Password
                      Text('Password', style: AppTheme.label),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordCtrl,
                        style: AppTheme.body.copyWith(color: AppTheme.textPrimary),
                        obscureText: _obscure,
                        decoration: AppTheme.inputDecoration(
                          '••••••••',
                          icon: Icons.lock_outline,
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: AppTheme.pinkMuted,
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) =>
                            v != null && v.length >= 6 ? null : 'Min 6 characters',
                      ),
                      const SizedBox(height: 8),

                      // Forgot password
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _forgotPassword,
                          child: Text(
                            'Forgot Password?',
                            style: AppTheme.caption.copyWith(
                                color: AppTheme.gold, fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Error
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.error.withOpacity(0.4)),
                          ),
                          child: Text(_error!,
                              style: AppTheme.caption.copyWith(color: AppTheme.error)),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Sign in button
                      GestureDetector(
                        onTap: _loading ? null : _signIn,
                        child: Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: AppTheme.pinkGradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.pink.withOpacity(0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Center(
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(
                                    _demoMode ? 'Enter Demo' : 'Sign In',
                                    style: AppTheme.buttonText,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Create account
                      Center(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const RegisterScreen())),
                          child: Text(
                            'Create Account',
                            style: AppTheme.body.copyWith(
                                color: AppTheme.pinkLight),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
