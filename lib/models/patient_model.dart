class PatientModel {
  final String patientId;
  final String name;
  final int age;
  final String doctorId;
  final String deviceId;
  final int registrationDate;
  final String status;
  final String riskLevel;
  final String? phone;
  final String? guardianPhone;

  const PatientModel({
    required this.patientId,
    required this.name,
    required this.age,
    required this.doctorId,
    required this.deviceId,
    required this.registrationDate,
    required this.status,
    required this.riskLevel,
    this.phone,
    this.guardianPhone,
  });

  factory PatientModel.fromMap(String id, Map<dynamic, dynamic> map) {
    return PatientModel(
      patientId: id,
      name: map['name'] ?? '',
      age: (map['age'] ?? 0) as int,
      doctorId: map['doctorId'] ?? '',
      deviceId: map['deviceId'] ?? '',
      registrationDate: (map['registrationDate'] ?? 0) as int,
      status: map['status'] ?? 'active',
      riskLevel: map['riskLevel'] ?? 'normal',
      phone: map['phone'],
      guardianPhone: map['guardianPhone'],
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'age': age,
        'doctorId': doctorId,
        'deviceId': deviceId,
        'registrationDate': registrationDate,
        'status': status,
        'riskLevel': riskLevel,
        if (phone != null) 'phone': phone,
        if (guardianPhone != null) 'guardianPhone': guardianPhone,
      };

  PatientModel copyWith({String? riskLevel, String? status}) {
    return PatientModel(
      patientId: patientId,
      name: name,
      age: age,
      doctorId: doctorId,
      deviceId: deviceId,
      registrationDate: registrationDate,
      status: status ?? this.status,
      riskLevel: riskLevel ?? this.riskLevel,
      phone: phone,
      guardianPhone: guardianPhone,
    );
  }
}
