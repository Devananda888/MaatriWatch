import 'package:firebase_database/firebase_database.dart';
import '../models/patient_model.dart';
import '../models/vitals_model.dart';
import '../models/alert_model.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';

/// Demo-mode mock data for "Priya Sharma" (Device: P001)
class DemoData {
  static final PatientModel patient = PatientModel(
    patientId: 'demo_priya',
    name: AppConstants.demoPatientName,
    age: 26,
    doctorId: 'demo_doctor',
    deviceId: AppConstants.demoDeviceId,
    registrationDate: DateTime.now()
        .subtract(const Duration(days: 14))
        .millisecondsSinceEpoch,
    status: 'active',
    riskLevel: AppConstants.riskNormal,
    phone: '+91 9876543210',
    guardianPhone: '+91 9123456789',
  );

  static VitalsModel vitals({bool pph = false}) => VitalsModel(
        heartRate: pph ? 118 : 78,
        spo2: pph ? 91 : 98,
        temperature: pph ? 35.2 : 37.1,
        baselineHR: 75,
        baselineTemp: 37.0,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

  static AlertModel pphAlert() => AlertModel(
        alertId: 'demo_alert_001',
        patientId: 'demo_priya',
        type: AppConstants.alertPphRisk,
        heartRate: 118,
        spo2: 91,
        temperature: 35.2,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        resolved: false,
      );

  static List<VitalsHistoryEntry> history() {
    final now = DateTime.now();
    return List.generate(24, (i) {
      final hr = 72.0 + (i % 4) * 3;
      return VitalsHistoryEntry(
        recordId: 'h$i',
        heartRate: hr,
        spo2: 97 - (i % 3) * 0.5,
        temperature: 36.8 + (i % 5) * 0.1,
        timestamp: now
            .subtract(Duration(hours: 24 - i))
            .millisecondsSinceEpoch,
      );
    });
  }
}

class FirebaseService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // ── PATIENTS ─────────────────────────────────────────

  Future<void> createPatient(PatientModel patient) async {
    await _db
        .child('patients/${patient.patientId}')
        .set(patient.toMap());
  }

  Stream<List<PatientModel>> watchDoctorPatients(String doctorId) {
    return _db
        .child('patients')
        .orderByChild('doctorId')
        .equalTo(doctorId)
        .onValue
        .map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) return [];
      final map = snap.value as Map<dynamic, dynamic>;
      return map.entries
          .map((e) => PatientModel.fromMap(
              e.key as String, e.value as Map<dynamic, dynamic>))
          .toList();
    });
  }

  Future<PatientModel?> getPatient(String patientId) async {
    final snap = await _db.child('patients/$patientId').get();
    if (!snap.exists) return null;
    return PatientModel.fromMap(
        patientId, snap.value as Map<dynamic, dynamic>);
  }

  Future<void> updatePatientRisk(String patientId, String riskLevel) async {
    await _db.child('patients/$patientId/riskLevel').set(riskLevel);
  }

  Future<String> generatePatientId() async {
    final ref = _db.child('patients').push();
    return ref.key!;
  }

  // ── VITALS ────────────────────────────────────────────

  Stream<VitalsModel?> watchLatestVitals(String patientId) {
    return _db.child('vitals/$patientId/latest').onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) return null;
      return VitalsModel.fromMap(snap.value as Map<dynamic, dynamic>);
    });
  }

  Future<List<VitalsHistoryEntry>> getVitalsHistory(String patientId,
      {int hours = 24}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(hours: hours))
        .millisecondsSinceEpoch;
    final snap = await _db
        .child('vitals/$patientId/history')
        .orderByChild('timestamp')
        .startAt(cutoff)
        .get();
    if (!snap.exists || snap.value == null) return [];
    final map = snap.value as Map<dynamic, dynamic>;
    final entries = map.entries
        .map((e) => VitalsHistoryEntry.fromMap(
            e.key as String, e.value as Map<dynamic, dynamic>))
        .toList();
    entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return entries;
  }

  Future<void> saveVitals(String patientId, VitalsModel vitals) async {
    final histRef = _db.child('vitals/$patientId/history').push();
    await Future.wait([
      _db.child('vitals/$patientId/latest').set(vitals.toMap()),
      histRef.set({
        'heartRate': vitals.heartRate,
        'spo2': vitals.spo2,
        'temperature': vitals.temperature,
        'timestamp': vitals.timestamp,
      }),
    ]);
  }

  // ── ALERTS ────────────────────────────────────────────

  Future<void> createAlert(AlertModel alert) async {
    await _db
        .child('alerts/${alert.patientId}/${alert.alertId}')
        .set(alert.toMap());
  }

  Future<void> resolveAlert(String patientId, String alertId) async {
    await _db.child('alerts/$patientId/$alertId').update({
      'resolved': true,
      'resolvedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Stream<List<AlertModel>> watchPatientAlerts(String patientId) {
    return _db.child('alerts/$patientId').onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) return [];
      final map = snap.value as Map<dynamic, dynamic>;
      return map.entries
          .map((e) => AlertModel.fromMap(
              e.key as String, patientId, e.value as Map<dynamic, dynamic>))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
  }

  Stream<List<AlertModel>> watchAllDoctorAlerts(List<String> patientIds) {
    // We merge per-patient streams — for simplicity, reload on any change.
    // In production, use a composite stream.
    return Stream.periodic(const Duration(seconds: 10)).asyncMap((_) async {
      final all = <AlertModel>[];
      for (final pid in patientIds) {
        final snap = await _db.child('alerts/$pid').get();
        if (!snap.exists || snap.value == null) continue;
        final map = snap.value as Map<dynamic, dynamic>;
        all.addAll(map.entries.map((e) => AlertModel.fromMap(
            e.key as String, pid, e.value as Map<dynamic, dynamic>)));
      }
      all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return all.where((a) => !a.resolved).toList();
    });
  }

  // ── MOOD ──────────────────────────────────────────────

  Future<void> saveMood(
      String patientId, int response, String label) async {
    final ref = _db.child('mood/$patientId').push();
    await ref.set({
      'response': response.toString(),
      'label': label,
      'date': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── EPDS ──────────────────────────────────────────────

  Future<void> saveEpds(
      String patientId, int score, List<int> responses) async {
    final ref = _db.child('epds/$patientId').push();
    await ref.set({
      'score': score,
      'date': DateTime.now().millisecondsSinceEpoch,
      'flagged': score >= AppConstants.epdsHighThreshold,
      'responses': responses,
    });
  }

  Future<Map<String, dynamic>?> getLatestEpds(String patientId) async {
    final snap = await _db.child('epds/$patientId').limitToLast(1).get();
    if (!snap.exists || snap.value == null) return null;
    final map = snap.value as Map<dynamic, dynamic>;
    return map.values.first as Map<String, dynamic>?;
  }

  // ── THERAPY ───────────────────────────────────────────

  Future<void> saveTherapySession({
    required String patientId,
    required String type,
    required int duration,
    required double hrBefore,
    required double hrAfter,
  }) async {
    final ref = _db.child('therapy/$patientId').push();
    await ref.set({
      'type': type,
      'completedAt': DateTime.now().millisecondsSinceEpoch,
      'duration': duration,
      'hrBefore': hrBefore,
      'hrAfter': hrAfter,
    });
  }

  // ── FALLS ─────────────────────────────────────────────

  Future<void> recordFall(String patientId, bool cancelled) async {
    final ref = _db.child('falls/$patientId').push();
    await ref.set({
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'cancelled': cancelled,
      'alertSent': !cancelled,
    });
  }

  // ── GDM / THYROID ─────────────────────────────────────

  Future<Map<String, dynamic>?> getGdmResult(String patientId) async {
    final snap = await _db.child('gdm/$patientId').get();
    if (!snap.exists) return null;
    return Map<String, dynamic>.from(snap.value as Map);
  }

  Future<Map<String, dynamic>?> getThyroidResult(String patientId) async {
    final snap = await _db.child('thyroid/$patientId').get();
    if (!snap.exists) return null;
    return Map<String, dynamic>.from(snap.value as Map);
  }

  // ── HRV ───────────────────────────────────────────────

  Future<bool?> getTodayHrvLow(String patientId) async {
    final today = DateTime.now();
    final key =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final snap = await _db.child('hrv/$patientId/$key').get();
    if (!snap.exists) return null;
    final map = snap.value as Map<dynamic, dynamic>;
    return map['low'] as bool?;
  }

  // ── SOS ───────────────────────────────────────────────

  Future<void> sendSosAlert(String patientId, VitalsModel vitals) async {
    final alertRef = _db.child('alerts/$patientId').push();
    final alert = AlertModel(
      alertId: alertRef.key!,
      patientId: patientId,
      type: AppConstants.alertSosManual,
      heartRate: vitals.heartRate,
      spo2: vitals.spo2,
      temperature: vitals.temperature,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      resolved: false,
    );
    await alertRef.set(alert.toMap());
  }
}
