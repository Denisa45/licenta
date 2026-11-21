import 'package:flutter/material.dart';

import 'l10n.dart';
import 'screens/login_screen.dart';
import 'screens/path_screen.dart';
import 'screens/practice_screen.dart';
import 'screens/progress_screen.dart';
import 'services/auth_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadLanguage();
  // Verifică tokenul salvat; AuthGate așteaptă până e gata.
  AuthService.instance.init();
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
    final auth = AuthService.instance;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (!auth.ready) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // Keyed by user id so the screens reload their data after a new sign-in.
        final user = auth.currentUser;
        if (user != null) {
          return HomeShell(key: ValueKey(user.id));
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
