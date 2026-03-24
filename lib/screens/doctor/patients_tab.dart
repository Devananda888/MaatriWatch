import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/patient_model.dart';
import '../../services/firebase_service.dart';
import '../../utils/theme.dart';
import '../../utils/helpers.dart';
import '../../widgets/patient_card.dart';
import '../../widgets/mother_silhouette_bg.dart';
import 'patient_detail_screen.dart';
import 'add_patient_sheet.dart';

class PatientsTab extends StatefulWidget {
  final String doctorId;
  final String doctorName;
  final bool demoMode;

  const PatientsTab({
    super.key,
    required this.doctorId,
    required this.doctorName,
    this.demoMode = false,
  });

  @override
  State<PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<PatientsTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  List<PatientModel> _demoPatients() => [
        DemoData.patient,
        PatientModel(
          patientId: 'demo_anjali',
          name: 'Anjali Singh',
          age: 28,
          doctorId: 'demo_doctor',
          deviceId: 'P002',
          registrationDate: DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch,
          status: 'active',
          riskLevel: 'warning',
        ),
        PatientModel(
          patientId: 'demo_kavya',
          name: 'Kavya Reddy',
          age: 24,
          doctorId: 'demo_doctor',
          deviceId: 'P003',
          registrationDate: DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch,
          status: 'active',
          riskLevel: 'normal',
        ),
      ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _buildHeader(int count) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning,' : hour < 17 ? 'Good afternoon,' : 'Good evening,';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A0A0F), Color(0xFF0D0D0D)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0, top: -10,
            child: Opacity(
              opacity: 0.05,
              child: Image.asset(
                'assets/images/mother_child_silhouette.png',
                width: 160, height: 180,
                color: AppTheme.gold, colorBlendMode: BlendMode.srcIn,
                errorBuilder: (_, __, ___) => const SizedBox(width: 160, height: 180),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting, style: AppTheme.body.copyWith(color: AppTheme.textSecondary)),
              Text('Dr. ${widget.doctorName}', style: AppTheme.headline),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: AppTheme.success),
                  ),
                  const SizedBox(width: 6),
                  Text('$count patients monitored', style: AppTheme.caption),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.read<FirebaseService>();

    Widget buildBody(List<PatientModel> patients) {
      final filtered = _query.isEmpty
          ? patients
          : patients.where((p) =>
              p.name.toLowerCase().contains(_query.toLowerCase())).toList();

      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(patients.length)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                style: AppTheme.body.copyWith(color: AppTheme.textPrimary),
                onChanged: (v) => setState(() => _query = v),
                decoration: AppTheme.inputDecoration(
                  'Search patients…', icon: Icons.search),
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text('No patients found', style: AppTheme.caption),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final patient = filtered[i];
                    return PatientCard(
                      patient: patient,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PatientDetailScreen(
                            patient: patient,
                            demoMode: widget.demoMode,
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.doctorBg,
      body: widget.demoMode
          ? buildBody(_demoPatients())
          : StreamBuilder<List<PatientModel>>(
              stream: svc.watchDoctorPatients(widget.doctorId),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppTheme.pink));
                }
                return buildBody(snap.data ?? []);
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.pink,
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) =>
              AddPatientSheet(doctorId: widget.doctorId, demoMode: widget.demoMode),
        ),
        child: const Icon(Icons.person_add_outlined, color: Colors.white),
      ),
    );
  }
}
