// lib/services/api_client.dart
//
// Cereri HTTP/JSON către server (backend/). Trimite tokenul JWT primit la
// autentificare în antetul 'Authorization: Bearer ...'. Tokenul e păstrat în
// shared_preferences, ca utilizatorul să rămână autentificat după repornire.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Eroare de la server. [code] e câmpul 'detail' din răspuns
/// (ex. 'invalid-credential'), sau 'network-request-failed' fără conexiune.
class ApiException implements Exception {
  final String code;
  final int? statusCode;

  const ApiException(this.code, [this.statusCode]);

  @override
  String toString() => code;
}

class ApiClient {
  ApiClient._();
  static final instance = ApiClient._();

  static const _tokenKey = 'auth_token';
  static const _timeout = Duration(seconds: 15);

  final _http = http.Client();
  String? _token;

  /// Apelat când serverul spune că tokenul nu mai e valid (401).
  void Function()? onUnauthorized;

  bool get hasToken => _token != null;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body);

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final request = http.Request(method, Uri.parse('$apiBaseUrl$path'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'application/json';
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    if (body != null) request.body = jsonEncode(body);

    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(request).timeout(_timeout),
      );
    } on TimeoutException {
      throw const ApiException('network-request-failed');
    } on http.ClientException {
      throw const ApiException('network-request-failed');
    }

    final text = utf8.decode(res.bodyBytes);
    final data = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    if (res.statusCode == 401 && _token != null && !path.startsWith('/auth/')) {
      onUnauthorized?.call();
    }
    final detail = data is Map ? data['detail'] : null;
    throw ApiException(
      detail is String ? detail : 'http-${res.statusCode}',
      res.statusCode,
    );
  }
}
