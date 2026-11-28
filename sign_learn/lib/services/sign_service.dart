// lib/services/sign_service.dart
//
// Lecțiile (semnele), de la GET /signs, în ordinea din drumul de învățare.

import '../models/sign.dart';
import 'api_client.dart';

class SignService {
  SignService._();
  static final instance = SignService._();

  Future<List<Sign>> all() async {
    final list = await ApiClient.instance.get('/signs') as List;
    return [for (final d in list) Sign.fromJson(d as Map<String, dynamic>)];
  }
}
