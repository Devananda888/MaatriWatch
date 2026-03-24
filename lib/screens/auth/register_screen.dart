import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../utils/theme.dart';
import '../../utils/constants.dart';
import '../../widgets/mother_silhouette_bg.dart';
import '../doctor/doctor_dashboard.dart';
import '../patient/patient_dashboard.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _role = AppConstants.rolePatient;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _passwordCtrl.dispose(); _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final auth = context.read<AuthService>();
      final user = await auth.register(
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        phone: _phoneCtrl.text,
        role: _role,
      );
      if (!mounted) return;
      if (user.role == AppConstants.roleDoctor) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => DoctorDashboard(userModel: user)),
          (_) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => PatientDashboard(userModel: user)),
          (_) => false,
        );
      }
    } catch (e) {
      setState(() { _loading = false; _error = e.toString().replaceAll('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: MotherSilhouetteBg(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Back button
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.pinkMuted.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new, size: 16, color: AppTheme.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.pinkMuted.withOpacity(0.4), width: 1),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create Account', style: AppTheme.headlineLarge),
                        const SizedBox(height: 4),
                        Text('Join MaatriWatch', style: AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
                        const SizedBox(height: 24),
                        _field('Full Name', _nameCtrl, Icons.person_outline,
                            validator: (v) => v != null && v.trim().isNotEmpty ? null : 'Required'),
                        const SizedBox(height: 14),
                        _field('Email', _emailCtrl, Icons.email_outlined,
                            type: TextInputType.emailAddress,
                            validator: (v) => v != null && v.contains('@') ? null : 'Enter valid email'),
                        const SizedBox(height: 14),
                        _field('Password', _passwordCtrl, Icons.lock_outline,
                            obscure: true,
                            validator: (v) => v != null && v.length >= 6 ? null : 'Min 6 characters'),
                        const SizedBox(height: 14),
                        _field('Phone', _phoneCtrl, Icons.phone_outlined,
                            type: TextInputType.phone),
                        const SizedBox(height: 14),

                        // Role selector
                        Text('I am a...', style: AppTheme.label),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _roleChip(AppConstants.rolePatient, '🤱 Patient'),
                            const SizedBox(width: 12),
                            _roleChip(AppConstants.roleDoctor, '👨‍⚕️ Doctor'),
                          ],
                        ),
                        const SizedBox(height: 24),

                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.error.withOpacity(0.4)),
                            ),
                            child: Text(_error!, style: AppTheme.caption.copyWith(color: AppTheme.error)),
                          ),
                          const SizedBox(height: 16),
                        ],

                        GestureDetector(
                          onTap: _loading ? null : _register,
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
                                  ? const SizedBox(width: 22, height: 22,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : Text('Create Account', style: AppTheme.buttonText),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    TextInputType? type,
    bool obscure = false,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.label),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          style: AppTheme.body.copyWith(color: AppTheme.textPrimary),
          keyboardType: type,
          obscureText: obscure && _obscure,
          decoration: AppTheme.inputDecoration('', icon: icon).copyWith(
            suffixIcon: obscure
                ? IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppTheme.pinkMuted, size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : null,
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _roleChip(String role, String label) {
    final isSelected = _role == role;
    return GestureDetector(
      onTap: () => setState(() => _role = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.pinkMuted.withOpacity(0.3) : AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.pink : AppTheme.pinkMuted.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? AppTheme.pinkGlow : [],
        ),
        child: Text(label, style: AppTheme.body.copyWith(
          color: isSelected ? AppTheme.pinkLight : AppTheme.textSecondary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        )),
      ),
    );
  }
}
