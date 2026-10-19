import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'l10n.dart';
import 'screens/login_screen.dart';
import 'screens/path_screen.dart';
import 'screens/practice_screen.dart';
import 'screens/progress_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await loadLanguage();
  runApp(const SignLearnApp());
}

class SignLearnApp extends StatelessWidget {
  const SignLearnApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Keyed by the language: switching it rebuilds every screen with new texts.
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLang,
      builder: (context, lang, _) => MaterialApp(
        key: ValueKey(lang),
        title: tr('Mână în mână', 'Hand in Hand'),
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // Keyed by uid so the screens reload their data after a new sign-in.
        if (snapshot.hasData) {
          return HomeShell(key: ValueKey(snapshot.data!.uid));
        }
        return const LoginScreen();
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  // Only the visible tab is built, so the camera is closed when you leave Exersare.
  static const List<Widget> _pages = [
    PathScreen(),
    PracticeScreen(),
    ProgressScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.route),
            label: tr('Drumul meu', 'My path'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.back_hand_outlined),
            selectedIcon: const Icon(Icons.back_hand),
            label: tr('Exersare', 'Practice'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights),
            label: tr('Progres', 'Progress'),
          ),
        ],
      ),
    );
  }
}
