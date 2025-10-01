import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'screens/sign_in_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (kDebugMode) {
    final host = 'localhost'; // Android emulatorなら '10.0.2.2'
    // Firestore emulator
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
      sslEnabled: false,
    );
    // Auth emulator
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    // Storage emulator (uncomment after adding firebase_storage to pubspec)
    // FirebaseStorage.instance.useStorageEmulator(host, 9199);
  }
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

/// サインイン状態で画面出し分け（Debug時は自動サインインを試みる）
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _attemptedAutoSignIn = false;

  Future<void> _tryDevAutoSignIn() async {
    if (!kDebugMode || _attemptedAutoSignIn) return;
    _attemptedAutoSignIn = true;
    const devEmail = String.fromEnvironment('DEV_EMAIL');
    const devPassword = String.fromEnvironment('DEV_PASSWORD');
    try {
      if (devEmail.isNotEmpty && devPassword.isNotEmpty) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: devEmail,
          password: devPassword,
        );
      } else {
        // フォールバック：匿名サインイン（Auth Emulator 前提）
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      debugPrint('Dev auto sign-in failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) {
          // Debug時は一度だけ自動サインインを試す
          _tryDevAutoSignIn();
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return HomeScreen(user: user);
      },
    );
  }
}
