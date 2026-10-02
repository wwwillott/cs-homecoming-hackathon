import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthSession {
  const AuthSession({required this.userId, required this.username});

  final String userId;
  final String username;
}

/// Simple username/password auth against the Orbit API.
class AuthService {
  AuthService({
    String apiUrl = const String.fromEnvironment(
      'ORBIT_API_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
    http.Client? client,
  })  : _apiUri = Uri.parse(apiUrl),
        _client = client ?? http.Client();

  final Uri _apiUri;
  final http.Client _client;

  Future<AuthSession> register({
    required String username,
    required String password,
  }) =>
      _authenticate('/api/auth/register', username: username, password: password);

  Future<AuthSession> login({
    required String username,
    required String password,
  }) =>
      _authenticate('/api/auth/login', username: username, password: password);

  Future<AuthSession> _authenticate(
    String path, {
    required String username,
    required String password,
  }) async {
    final response = await _client.post(
      _apiUri.replace(path: path, query: null, fragment: null),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username.trim(), 'password': password}),
    );
    final body = _jsonBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_apiError(body, response.statusCode));
    }
    return AuthSession(
      userId: body['user_id'] as String,
      username: body['username'] as String? ?? username.trim(),
    );
  }

  Map<String, dynamic> _jsonBody(http.Response response) {
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      return {};
    }
  }

  String _apiError(Map<String, dynamic> body, int status) {
    final detail = body['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    return 'Request failed with status $status.';
  }

  void dispose() => _client.close();
}
