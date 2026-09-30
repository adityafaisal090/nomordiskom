import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Centralized HTTP client with automatic 401 handling.
/// On any 401 response, triggers force-logout callback.
class ApiService {
  // Base URL config: Android emulator uses 10.0.2.2, web uses localhost
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000/api';
    }
    // Android emulator
    return 'http://10.0.2.2:3000/api';
  }

  String? _token;
  VoidCallback? _onUnauthorized;

  /// Set the JWT token for authenticated requests
  void setToken(String? token) {
    _token = token;
  }

  /// Set callback for 401 responses (force-logout)
  void setOnUnauthorized(VoidCallback callback) {
    _onUnauthorized = callback;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  /// Handle response — check for 401 and trigger force-logout
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode == 401) {
      _onUnauthorized?.call();
      throw ApiException('Sesi telah berakhir. Silakan login kembali.', 401);
    }

    final body = jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw ApiException(
      body['message'] ?? 'Terjadi kesalahan',
      response.statusCode,
    );
  }

  Future<dynamic> get(String endpoint) async {
    final response = await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: _headers,
    );
    return _handleResponse(response);
  }

  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    final response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  Future<dynamic> patch(String endpoint, {Map<String, dynamic>? body}) async {
    final response = await http.patch(
      Uri.parse('$baseUrl$endpoint'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}
