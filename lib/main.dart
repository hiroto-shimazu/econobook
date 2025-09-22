import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'screens/sign_in_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const EconoBookApp());
}

class EconoBookApp extends StatelessWidget {
  const EconoBookApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EconoBook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D80F2)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// サインイン状態で画面出し分け
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const SignInScreen();
        return HomeScreen(user: user);
      },
    );
  }
}
