// lib/services/robot_service.dart
//
// Trimite un semn mâinii robotice prin server (backend/):
//   POST /robot/commands {sign_id}   -> comanda, cu status 'pending'
//   GET  /robot/commands/{id}        -> statusul, verificat la fiecare secundă
// Raspberry Pi-ul (hw/command_listener.py) preia comanda de la server, mișcă
// mâna și schimbă statusul în 'processing', apoi 'completed' sau 'error'.

import 'dart:async';

import 'api_client.dart';

class RobotService {
  RobotService._();
  static final instance = RobotService._();

  static const _pollEvery = Duration(seconds: 1);
  static const _finalStates = {'completed', 'error', 'expired'};

  final _api = ApiClient.instance;

  /// Creates the command and returns the stream of its status.
  Future<Stream<String>> showSign(String signId) async {
    final cmd = await _api.post('/robot/commands', {'sign_id': signId});
    return _poll((cmd['id'] as num).toInt());
  }

  Stream<String> _poll(int id) async* {
    var last = '';
    while (true) {
      String status;
      try {
        final cmd = await _api.get('/robot/commands/$id');
        status = (cmd['status'] ?? 'pending').toString();
      } on ApiException {
        status = last.isEmpty ? 'pending' : last; // încearcă din nou
      }
      if (status != last) {
        last = status;
        yield status;
      }
      if (_finalStates.contains(status)) return;
      await Future<void>.delayed(_pollEvery);
    }
  }
}
