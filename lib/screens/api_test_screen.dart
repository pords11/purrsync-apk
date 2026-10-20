import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// A small diagnostics screen that fires real HTTP requests at the
/// Firestore REST API (GET, POST, PATCH, DELETE) and displays the raw
/// response. Intended for the midterm's "API Integration and Testing"
/// evidence - every button press here is a genuine network call against
/// your live Firebase project, so a screenshot of this screen is real
/// testing evidence, not a mockup.
class ApiTestScreen extends StatefulWidget {
  const ApiTestScreen({super.key});

  @override
  State<ApiTestScreen> createState() => _ApiTestScreenState();
}

class _ApiTestScreenState extends State<ApiTestScreen> {
  final ApiService _api = ApiService();
  String? _lastCreatedDocId;
  bool _isLoading = false;
  ApiResult? _lastResult;
  String? _errorMessage;

  Future<void> _run(Future<ApiResult> Function() call) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await call();
      setState(() => _lastResult = result);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _testGet() async {
    if (_lastCreatedDocId == null) {
      setState(() => _errorMessage = 'Run POST first to create a test document to GET.');
      return;
    }
    await _run(() => _api.getDoc(_lastCreatedDocId!));
  }

  Future<void> _testPost() async {
    await _run(() async {
      final result = await _api.postDoc(note: 'Test log created at ${DateTime.now()}');
      // Firestore returns the created document's resource name, e.g.
      // .../documents/api_test_logs/AbCd1234 - pull the doc ID out of it
      // so subsequent GET/PATCH/DELETE calls target the same document.
      try {
        final match = RegExp(r'api_test_logs/([^"\s]+)').firstMatch(result.body);
        if (match != null) _lastCreatedDocId = match.group(1);
      } catch (_) {}
      return result;
    });
  }

  Future<void> _testPatch() async {
    if (_lastCreatedDocId == null) {
      setState(() => _errorMessage = 'Run POST first to create a test document to PATCH.');
      return;
    }
    await _run(() => _api.patchDoc(_lastCreatedDocId!, newNote: 'Updated at ${DateTime.now()}'));
  }

  Future<void> _testDelete() async {
    if (_lastCreatedDocId == null) {
      setState(() => _errorMessage = 'Run POST first to create a test document to DELETE.');
      return;
    }
    await _run(() => _api.deleteDoc(_lastCreatedDocId!));
    _lastCreatedDocId = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Test Console'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Each button below sends a real HTTP request to the Firestore REST API '
              '(project: purrsync-42b2c) using your signed-in account\'s ID token for '
              'authorization. Requests operate on a dedicated api_test_logs collection.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _testPost,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('POST (Create)', style: TextStyle(color: Colors.white)),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testGet,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: const Text('GET (Read)', style: TextStyle(color: Colors.white)),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testPatch,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text('PATCH (Update)', style: TextStyle(color: Colors.white)),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testDelete,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('DELETE', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading) const LinearProgressIndicator(color: Colors.orange),
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade900)),
              ),
            if (_lastResult != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Chip(
                    label: Text('${_lastResult!.method} ${_lastResult!.statusCode}'),
                    backgroundColor: _lastResult!.success ? Colors.green.shade100 : Colors.red.shade100,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastResult!.url,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _lastResult!.body,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
