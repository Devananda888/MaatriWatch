import 'package:firebase_database/firebase_database.dart';

/// A small, transient live overlay for the patient's assigned wearable.
///
/// The REST home response remains available if this stream is denied or
/// disconnected. Firebase must never silently invent a reading.
abstract class PatientLiveVitalsSource {
  Stream<Map<String, dynamic>?> latestForPatient({
    required String hospitalId,
    required String patientId,
  });
}

class FirebasePatientLiveVitalsSource implements PatientLiveVitalsSource {
  FirebasePatientLiveVitalsSource({FirebaseDatabase? database})
      : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  @override
  Stream<Map<String, dynamic>?> latestForPatient({
    required String hospitalId,
    required String patientId,
  }) =>
      _database.ref('live_vitals/$hospitalId/$patientId').onValue.map((event) {
        final value = event.snapshot.value;
        return value is Map ? Map<String, dynamic>.from(value) : null;
      });
}
