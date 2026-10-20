import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Result of a single REST call, kept simple so it can be rendered
/// directly in the API Test Console UI.
class ApiResult {
  final int statusCode;
  final String method;
  final String url;
  final String body;
  final bool success;

  ApiResult({
    required this.statusCode,
    required this.method,
    required this.url,
    required this.body,
    required this.success,
  });
}

/// Talks directly to the Cloud Firestore REST API over HTTPS using genuine
/// GET / POST / PATCH / DELETE requests, authorized with the signed-in
/// user's Firebase ID token.
///
/// This exists alongside FirebaseService (which uses the Firebase SDK for
/// the app's day-to-day CRUD) specifically to demonstrate and test raw HTTP
/// API integration, as required by the midterm checklist. Calls in this
/// service operate on a dedicated `api_test_logs` collection so they never
/// touch real cat data.
class ApiService {
  static const String _projectId = 'purrsync-42b2c';
  static const String _baseUrl =
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';

  Future<String> _authHeader() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('You must be signed in to call the API.');
    }
    return 'Bearer ${await user.getIdToken()}';
  }

  /// GET /api_test_logs/{docId} - reads a single test document.
  Future<ApiResult> getDoc(String docId) async {
    final url = '$_baseUrl/api_test_logs/$docId';
    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': await _authHeader()},
    );
    return ApiResult(
      statusCode: response.statusCode,
      method: 'GET',
      url: url,
      body: _pretty(response.body),
      success: response.statusCode >= 200 && response.statusCode < 300,
    );
  }

  /// POST /api_test_logs - creates a new test document with an
  /// auto-generated ID and returns the created resource.
  Future<ApiResult> postDoc({required String note}) async {
    const url = '$_baseUrl/api_test_logs';
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': await _authHeader(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'fields': {
          'note': {'stringValue': note},
          'createdAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        },
      }),
    );
    return ApiResult(
      statusCode: response.statusCode,
      method: 'POST',
      url: url,
      body: _pretty(response.body),
      success: response.statusCode >= 200 && response.statusCode < 300,
    );
  }

  /// PATCH /api_test_logs/{docId}?updateMask.fieldPaths=note - updates a
  /// single field on an existing test document.
  Future<ApiResult> patchDoc(String docId, {required String newNote}) async {
    final url = '$_baseUrl/api_test_logs/$docId?updateMask.fieldPaths=note';
    final response = await http.patch(
      Uri.parse(url),
      headers: {
        'Authorization': await _authHeader(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'fields': {
          'note': {'stringValue': newNote},
        },
      }),
    );
    return ApiResult(
      statusCode: response.statusCode,
      method: 'PATCH',
      url: url,
      body: _pretty(response.body),
      success: response.statusCode >= 200 && response.statusCode < 300,
    );
  }

  /// DELETE /api_test_logs/{docId} - removes a test document.
  Future<ApiResult> deleteDoc(String docId) async {
    final url = '$_baseUrl/api_test_logs/$docId';
    final response = await http.delete(
      Uri.parse(url),
      headers: {'Authorization': await _authHeader()},
    );
    return ApiResult(
      statusCode: response.statusCode,
      method: 'DELETE',
      url: url,
      // Firestore returns an empty body on a successful delete.
      body: response.body.isEmpty ? '{}' : _pretty(response.body),
      success: response.statusCode >= 200 && response.statusCode < 300,
    );
  }

  /// Fetches a live daily cat health and care fact from the public
  /// Cat Facts REST API (https://catfact.ninja/fact).
  /// Demonstrates external third-party public REST API consumption.
  Future<String> fetchDailyCatFact() async {
    try {
      final response = await http
          .get(Uri.parse('https://catfact.ninja/fact'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['fact'] as String? ??
            'Regular veterinary checkups and scheduled vaccinations keep your cat healthy and happy.';
      }
    } catch (_) {
      // Fallback tip if offline
    }
    return 'Regular veterinary checkups and scheduled vaccinations keep your cat healthy and happy.';
  }

  String _pretty(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return rawJson;
    }
  }
}
