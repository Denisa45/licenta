// lib/services/auth_service.dart
//
// Contul utilizatorului: creare cont, autentificare, ieșire. Înlocuiește
// Firebase Auth. AuthGate (main.dart) ascultă [AuthService.instance] și arată
// ecranul de login sau aplicația.

import 'package:flutter/foundation.dart';

import 'api_client.dart';

class AppUser {
  final int id;
  final String email;
  final String role;

  const AppUser({required this.id, required this.email, required this.role});

  factory AppUser.fromJson(Map<String, dynamic> d) => AppUser(
    id: (d['id'] as num).toInt(),
    email: (d['email'] ?? '').toString(),
    role: (d['role'] ?? 'user').toString(),
  );
}

class AuthService extends ChangeNotifier {
  AuthService._();
  static final instance = AuthService._();

  final _api = ApiClient.instance;

  AppUser? _user;
  bool _ready = false;

  AppUser? get currentUser => _user;

  /// False până când [init] verifică tokenul salvat.
  bool get ready => _ready;

  /// La pornire: dacă există un token salvat, îl verifică la server.
  Future<void> init() async {
    _api.onUnauthorized = signOut;
    await _api.loadToken();
    if (_api.hasToken) {
      try {
        _user = AppUser.fromJson(await _api.get('/auth/me'));
      } on ApiException catch (e) {
        // Fără conexiune păstrăm tokenul; un token invalid îl ștergem.
        if (e.statusCode == 401) await _api.setToken(null);
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) =>
      _authenticate('/auth/login', email, password);

  Future<void> register(String email, String password) =>
      _authenticate('/auth/register', email, password);

  Future<void> _authenticate(String path, String email, String password) async {
    final res = await _api.post(path, {'email': email, 'password': password});
    await _api.setToken(res['access_token'] as String);
    _user = AppUser.fromJson(res['user'] as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _api.setToken(null);
    _user = null;
    notifyListeners();
  }
}
