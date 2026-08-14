double? asDouble(Object? value) => value is num ? value.toDouble() : null;

int asInt(Object? value) => value is num ? value.toInt() : 0;

DateTime? asDateTime(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

Map<String, dynamic> asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

class HospitalMembership {
  const HospitalMembership({
    required this.hospitalId,
    required this.hospitalName,
    required this.role,
  });

  final String hospitalId;
  final String hospitalName;
  final String role;

  factory HospitalMembership.fromJson(Map<String, dynamic> json) => HospitalMembership(
        hospitalId: json['hospital_id'] as String,
        hospitalName: json['hospital_name'] as String? ?? 'Hospital',
        role: json['role'] as String? ?? '',
      );
}

class VitalReading {
  const VitalReading({
    required this.capturedAt,
    this.heartRate,
    this.spo2,
    this.temperature,
    this.systolic,
    this.diastolic,
    this.battery,
    this.bloodLoss,
    this.sampleCount,
  });

  final DateTime? capturedAt;
  final double? heartRate;
  final double? spo2;
  final double? temperature;
  final double? systolic;
  final double? diastolic;
  final double? battery;
  final double? bloodLoss;
  final int? sampleCount;

  factory VitalReading.fromJson(Map<String, dynamic> json) => VitalReading(
        capturedAt: asDateTime(json['captured_at']),
        heartRate: asDouble(json['heart_rate_bpm']),
        spo2: asDouble(json['spo2_percent']),
        temperature: asDouble(json['temperature_c']),
        systolic: asDouble(json['systolic_bp']),
        diastolic: asDouble(json['diastolic_bp']),
        battery: asDouble(json['battery_percent']),
        bloodLoss: asDouble(json['blood_loss_ml']),
        sampleCount: json['sample_count'] is num ? asInt(json['sample_count']) : null,
      );
}

class PatientSummary {
  const PatientSummary({
    required this.id,
    required this.name,
    required this.medicalRecordNumber,
    required this.status,
    required this.activeAlertCount,
    this.language,
    this.deliveryDate,
    this.latestVital,
    this.deviceLastSeenAt,
  });

  final String id;
  final String name;
  final String medicalRecordNumber;
  final String status;
  final int activeAlertCount;
  final String? language;
  final DateTime? deliveryDate;
  final VitalReading? latestVital;
  final DateTime? deviceLastSeenAt;

  factory PatientSummary.fromJson(Map<String, dynamic> json) {
    final device = asMap(json['device']);
    final latestVital = asMap(json['latest_vital']);
    return PatientSummary(
      id: json['id'] as String,
      name: json['full_name'] as String? ?? 'Unnamed patient',
      medicalRecordNumber: json['medical_record_number'] as String? ?? '—',
      status: json['status'] as String? ?? 'normal',
      activeAlertCount: asInt(json['active_alert_count']),
      language: json['preferred_language'] as String?,
      deliveryDate: asDateTime(json['delivery_date']),
      latestVital: latestVital.isEmpty ? null : VitalReading.fromJson(latestVital),
      deviceLastSeenAt: asDateTime(device['last_seen_at']),
    );
  }

  PatientSummary withLiveVital(Map<String, dynamic> live) {
    final liveStatus = live['status'] as String?;
    return PatientSummary(
      id: id,
      name: name,
      medicalRecordNumber: medicalRecordNumber,
      status: liveStatus == 'normal' || liveStatus == 'info' || liveStatus == 'warning' || liveStatus == 'critical'
          ? liveStatus!
          : status,
      activeAlertCount: activeAlertCount,
      language: language,
      deliveryDate: deliveryDate,
      latestVital: VitalReading.fromJson(live),
      deviceLastSeenAt: asDateTime(live['received_at']) ?? deviceLastSeenAt,
    );
  }
}

class AlertItem {
  const AlertItem({
    required this.id,
    required this.patientId,
    required this.severity,
    required this.status,
    required this.type,
    required this.message,
    required this.occurrenceCount,
    this.patientName,
    this.triggeredAt,
    this.lastSeenAt,
    this.updatedAt,
  });

  final String id;
  final String patientId;
  final String severity;
  final String status;
  final String type;
  final String message;
  final int occurrenceCount;
  final String? patientName;
  final DateTime? triggeredAt;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;

  factory AlertItem.fromJson(Map<String, dynamic> json) => AlertItem(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        severity: json['severity'] as String? ?? 'info',
        status: json['status'] as String? ?? 'open',
        type: json['alert_type'] as String? ?? 'Risk signal',
        message: json['message'] as String? ?? '',
        occurrenceCount: asInt(json['occurrence_count']),
        patientName: json['full_name'] as String?,
        triggeredAt: asDateTime(json['triggered_at']),
        lastSeenAt: asDateTime(json['last_seen_at']),
        updatedAt: asDateTime(json['updated_at']),
      );

  AlertItem copyWith({String? status, DateTime? updatedAt}) => AlertItem(
        id: id,
        patientId: patientId,
        severity: severity,
        status: status ?? this.status,
        type: type,
        message: message,
        occurrenceCount: occurrenceCount,
        patientName: patientName,
        triggeredAt: triggeredAt,
        lastSeenAt: lastSeenAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class ClinicalNote {
  const ClinicalNote({
    required this.id,
    required this.note,
    this.authorName,
    this.createdAt,
  });

  final String id;
  final String note;
  final String? authorName;
  final DateTime? createdAt;

  factory ClinicalNote.fromJson(Map<String, dynamic> json) => ClinicalNote(
        id: json['id'] as String,
        note: json['note'] as String? ?? '',
        authorName: json['author_display_name'] as String?,
        createdAt: asDateTime(json['created_at']),
      );
}

class PatientDetail {
  const PatientDetail({
    required this.patient,
    required this.status,
    this.latestVital,
    this.latestScreening,
  });

  final PatientSummary patient;
  final String status;
  final VitalReading? latestVital;
  final Map<String, dynamic>? latestScreening;

  factory PatientDetail.fromJson(Map<String, dynamic> json) {
    final patient = asMap(json['patient']);
    final vital = asMap(json['latest_vital']);
    return PatientDetail(
      patient: PatientSummary(
        id: patient['id'] as String,
        name: patient['full_name'] as String? ?? 'Unnamed patient',
        medicalRecordNumber: patient['medical_record_number'] as String? ?? '—',
        status: json['status'] as String? ?? 'normal',
        activeAlertCount: 0,
        language: patient['preferred_language'] as String?,
        deliveryDate: asDateTime(patient['delivery_date']),
        latestVital: vital.isEmpty ? null : VitalReading.fromJson(vital),
      ),
      status: json['status'] as String? ?? 'normal',
      latestVital: vital.isEmpty ? null : VitalReading.fromJson(vital),
      latestScreening: asMap(json['latest_screening']),
    );
  }
}
