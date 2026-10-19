// lib/l10n.dart
//
// Two app languages, Romanian (default) and English. Texts are written inline
// as tr('ro text', 'en text'). Changing the language rebuilds the whole app
// (main.dart keys MaterialApp by the language) and is remembered on the device.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLang { ro, en }

final appLang = ValueNotifier<AppLang>(AppLang.ro);

const _prefKey = 'app_lang';

/// Romanian or English text, depending on the current language.
String tr(String ro, String en) => appLang.value == AppLang.en ? en : ro;

Future<void> loadLanguage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_prefKey) == 'en') appLang.value = AppLang.en;
  } catch (_) {
    // No saved language: keep Romanian.
  }
}

Future<void> toggleLanguage() async {
  appLang.value = appLang.value == AppLang.ro ? AppLang.en : AppLang.ro;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, appLang.value.name);
  } catch (_) {}
}
