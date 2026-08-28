import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class PatientApi {
  PatientApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ??
                const String.fromEnvironment('API_BASE_URL',
                    defaultValue: 'http://localhost:8000/api/v1'))
            .replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;
  Future<Map<String, dynamic>> home() => _request('GET', '/patient/home');
  Future<Map<String, dynamic>> sos(String note) =>
      _request('POST', '/patient/sos', body: {'note': note});
  Future<Map<String, dynamic>> symptoms(List<String> symptoms, String notes) =>
      _request('POST', '/patient/symptoms',
          body: {'symptoms': symptoms, 'notes': notes});
  Future<Map<String, dynamic>> consents() =>
      _request('GET', '/patient/consents');
  Future<Map<String, dynamic>> setConsent(String type, bool granted) =>
      _request('PUT', '/patient/consents/$type', body: {'granted': granted});
  Future<Map<String, dynamic>> completeTask(String id, String status) =>
      _request('PATCH', '/patient/care-plan/$id', body: {'status': status});

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, dynamic>? body}) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw const PatientApiException('Please sign in again to continue.');
    }
    final response = await _client
        .send(http.Request(method, Uri.parse('$_baseUrl$path'))
          ..headers.addAll({
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            if (body != null) 'Content-Type': 'application/json'
          })
          ..body = body == null ? '' : jsonEncode(body))
        .then(http.Response.fromStream);
    final decoded =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final value = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw PatientApiException(
          value['message'] as String? ?? 'We could not complete that request.');
    }
    return value;
  }
}

class PatientApiException implements Exception {
  const PatientApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
