class AlertModel {
  final String alertId;
  final String patientId;
  final String type;
  final double heartRate;
  final double spo2;
  final double temperature;
  final int timestamp;
  final bool resolved;
  final int? resolvedAt;

  const AlertModel({
    required this.alertId,
    required this.patientId,
    required this.type,
    required this.heartRate,
    required this.spo2,
    required this.temperature,
    required this.timestamp,
    required this.resolved,
    this.resolvedAt,
  });

  factory AlertModel.fromMap(
      String alertId, String patientId, Map<dynamic, dynamic> map) {
    return AlertModel(
      alertId: alertId,
      patientId: patientId,
      type: map['type'] ?? '',
      heartRate: (map['heartRate'] ?? 0).toDouble(),
      spo2: (map['spo2'] ?? 0).toDouble(),
      temperature: (map['temperature'] ?? 0).toDouble(),
      timestamp: (map['timestamp'] ?? 0) as int,
      resolved: map['resolved'] == true,
      resolvedAt: map['resolvedAt'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'heartRate': heartRate,
        'spo2': spo2,
        'temperature': temperature,
        'timestamp': timestamp,
        'resolved': resolved,
        if (resolvedAt != null) 'resolvedAt': resolvedAt,
      };

  AlertModel copyWith({bool? resolved, int? resolvedAt}) {
    return AlertModel(
      alertId: alertId,
      patientId: patientId,
      type: type,
      heartRate: heartRate,
      spo2: spo2,
      temperature: temperature,
      timestamp: timestamp,
      resolved: resolved ?? this.resolved,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }
}
