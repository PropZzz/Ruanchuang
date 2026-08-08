import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
    : _httpClient = httpClient ?? http.Client(),
      _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/+$'), '');

  final http.Client _httpClient;
  final String _baseUrl;
  String? _token;

  void setToken(String? token) {
    _token = token?.trim().isEmpty == true ? null : token?.trim();
  }

  Uri _uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalized');
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
    };
  }

  Future<Object?> get(String path) => _send('GET', path);
  Future<Object?> post(String path, Object? body) => _send('POST', path, body: body);
  Future<Object?> put(String path, Object? body) => _send('PUT', path, body: body);
  Future<Object?> delete(String path) => _send('DELETE', path);

  Future<Object?> _send(String method, String path, {Object? body}) async {
    final uri = _uri(path);
    final encoded = body == null ? null : jsonEncode(body);
    final response = await switch (method) {
      'GET' => _httpClient.get(uri, headers: _headers()),
      'POST' => _httpClient.post(uri, headers: _headers(), body: encoded),
      'PUT' => _httpClient.put(uri, headers: _headers(), body: encoded),
      'DELETE' => _httpClient.delete(uri, headers: _headers()),
      _ => throw ApiException('Unsupported method: $method'),
    }.timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.body.isEmpty ? 'HTTP ${response.statusCode}' : response.body,
        statusCode: response.statusCode,
      );
    }

    if (response.body.trim().isEmpty) {
      return null;
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}
