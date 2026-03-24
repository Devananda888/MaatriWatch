class VitalsModel {
  final double heartRate;
  final double spo2;
  final double temperature;
  final double baselineHR;
  final double baselineTemp;
  final int timestamp;

  const VitalsModel({
    required this.heartRate,
    required this.spo2,
    required this.temperature,
    required this.baselineHR,
    required this.baselineTemp,
    required this.timestamp,
  });

  factory VitalsModel.fromMap(Map<dynamic, dynamic> map) {
    return VitalsModel(
      heartRate: (map['heartRate'] ?? 0).toDouble(),
      spo2: (map['spo2'] ?? 0).toDouble(),
      temperature: (map['temperature'] ?? 0).toDouble(),
      baselineHR: (map['baselineHR'] ?? 75).toDouble(),
      baselineTemp: (map['baselineTemp'] ?? 36.8).toDouble(),
      timestamp: (map['timestamp'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toMap() => {
        'heartRate': heartRate,
        'spo2': spo2,
        'temperature': temperature,
        'baselineHR': baselineHR,
        'baselineTemp': baselineTemp,
        'timestamp': timestamp,
      };
}

class VitalsHistoryEntry {
  final String recordId;
  final double heartRate;
  final double spo2;
  final double temperature;
  final int timestamp;

  const VitalsHistoryEntry({
    required this.recordId,
    required this.heartRate,
    required this.spo2,
    required this.temperature,
    required this.timestamp,
  });

  factory VitalsHistoryEntry.fromMap(String id, Map<dynamic, dynamic> map) {
    return VitalsHistoryEntry(
      recordId: id,
      heartRate: (map['heartRate'] ?? 0).toDouble(),
      spo2: (map['spo2'] ?? 0).toDouble(),
      temperature: (map['temperature'] ?? 0).toDouble(),
      timestamp: (map['timestamp'] ?? 0) as int,
    );
  }
}
