import 'package:flutter/material.dart';

import '../l10n.dart';

/// App bar button that switches between Romanian and English.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: toggleLanguage,
      icon: const Icon(Icons.translate),
      // Shows the language you switch TO.
      label: Text(appLang.value == AppLang.ro ? 'EN' : 'RO'),
    );
  }
}
