// lib/config.dart
//
// Adresa serverului (backend/). Se poate schimba la rulare, fără să modifici codul:
//   flutter run --dart-define=API_URL=http://192.168.1.10:8000
// Implicit: emulatorul Android vede calculatorul la 10.0.2.2, restul la localhost.
// Pe un telefon real pune IP-ul calculatorului din rețeaua Wi-Fi.

import 'package:flutter/foundation.dart';

const _fromEnv = String.fromEnvironment('API_URL');

String get apiBaseUrl {
  if (_fromEnv.isNotEmpty) return _fromEnv;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://localhost:8000';
}
