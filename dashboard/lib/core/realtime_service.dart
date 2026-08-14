import 'package:firebase_database/firebase_database.dart';

import 'models.dart';

/// RTDB is a transient overlay. A denied or disconnected stream must never
/// erase the authoritative REST list already shown to a clinician.
class RealtimeService {
  Stream<Map<String, Map<String, dynamic>>> liveVitals(String hospitalId) => FirebaseDatabase.instance
      .ref('live_vitals/$hospitalId')
      .onValue
      .map((event) {
    final source = asMap(event.snapshot.value);
    return source.map((key, value) => MapEntry(key, asMap(value)));
  });

  Stream<Map<String, Map<String, dynamic>>> liveAlerts(String hospitalId) => FirebaseDatabase.instance
      .ref('live_alerts/$hospitalId')
      .onValue
      .map((event) {
    final source = asMap(event.snapshot.value);
    return source.map((key, value) => MapEntry(key, asMap(value)));
  });
}
