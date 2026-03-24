import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/patient_model.dart';
import '../../services/firebase_service.dart';
import '../../utils/theme.dart';

class AddPatientSheet extends StatefulWidget {
  final String doctorId;
  final bool demoMode;

  const AddPatientSheet({super.key, required this.doctorId, this.demoMode = false});

  @override
  State<AddPatientSheet> createState() => _AddPatientSheetState();
}

class _AddPatientSheetState extends State<AddPatientSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _guardianCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _ageCtrl.dispose(); _phoneCtrl.dispose();
    _guardianCtrl.dispose(); _deviceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final svc = context.read<FirebaseService>();
      final id = await svc.generatePatientId();
      final patient = PatientModel(
        patientId: id,
        name: _nameCtrl.text.trim(),
        age: int.tryParse(_ageCtrl.text) ?? 0,
        doctorId: widget.doctorId,
        deviceId: _deviceCtrl.text.trim(),
        registrationDate: DateTime.now().millisecondsSinceEpoch,
        status: 'active',
        riskLevel: 'normal',
        phone: _phoneCtrl.text.trim(),
        guardianPhone: _guardianCtrl.text.trim(),
      );
      await svc.createPatient(patient);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.pinkMuted.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Add New Patient', style: AppTheme.subhead),
            const SizedBox(height: 20),
            _field('Patient Name', _nameCtrl, Icons.person_outline,
                validator: (v) => v != null && v.isNotEmpty ? null : 'Required'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field('Age', _ageCtrl, Icons.cake_outlined,
                    type: TextInputType.number,
                    validator: (v) => v != null && v.isNotEmpty ? null : 'Required')),
                const SizedBox(width: 12),
                Expanded(child: _field('Device ID', _deviceCtrl, Icons.devices)),
              ],
            ),
            const SizedBox(height: 12),
            _field('Phone Number', _phoneCtrl, Icons.phone_outlined,
                type: TextInputType.phone),
            const SizedBox(height: 12),
            _field('Guardian Phone', _guardianCtrl, Icons.contact_phone_outlined,
                type: TextInputType.phone),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _loading ? null : _submit,
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppTheme.pinkGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                    color: AppTheme.pink.withOpacity(0.35),
                    blurRadius: 16, offset: const Offset(0, 6),
                  )],
                ),
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : Text('Add Patient', style: AppTheme.buttonText),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, IconData icon,
      {TextInputType? type, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      style: AppTheme.body.copyWith(color: AppTheme.textPrimary),
      keyboardType: type,
      decoration: AppTheme.inputDecoration(label, icon: icon),
      validator: validator,
    );
  }
}
