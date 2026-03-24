class UserModel {
  final String uid;
  final String name;
  final String role;
  final String email;
  final String phone;
  final String? doctorId;
  final String? patientId;
  final String? deviceId;
<br>  const UserModel({
    required this.uid,
    required this.name,
    required this.role,
    required this.email,
    required this.phone,
    this.doctorId,
    this.patientId,
    this.deviceId,
  });

  factory UserModel.fromMap(String uid, Map<dynamic, dynamic> map) {
    return UserModel(
      uid: uid,
      name: map['name'] ?? '',
      role: map['role'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      doctorId: map['doctorId'],
      patientId: map['patientId'],
      deviceId: map['deviceId'],
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'role': role,
        'email': email,
        'phone': phone,
        if (doctorId != null) 'doctorId': doctorId,
        if (patientId != null) 'patientId': patientId,
        if (deviceId != null) 'deviceId': deviceId,
      };
}
