import 'dart:async';
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
  // Emulator usage should be explicit. In earlier code we enabled emulators
  // whenever kDebugMode was true which caused accidental emulator binding on
  // real devices (where 'localhost' is not reachable). Require an explicit
  // --dart-define=USE_FIREBASE_EMULATOR=true to turn on emulator mode.
  const useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR',
      defaultValue: false);
  if (kDebugMode && useEmulator) {
    final host = const String.fromEnvironment('FIREBASE_EMULATOR_HOST',
        defaultValue: 'localhost'); // Android emulatorなら '10.0.2.2'
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
  // If auth stream does not emit within this duration, we consider it a
  // transient failure and fall back to showing the SignInScreen.
  static const _authStreamTimeout = Duration(seconds: 5);
  Timer? _authTimeoutTimer;
  bool _authTimedOut = false;

  Future<void> _tryDevAutoSignIn() async {
    if (!kDebugMode || _attemptedAutoSignIn) return;
    // mark that we've started an attempt and trigger a rebuild so the
    // loading indicator is shown while attempting.
    if (mounted) setState(() {
      _attemptedAutoSignIn = true;
    });
    const devEmail = String.fromEnvironment('DEV_EMAIL');
    const devPassword = String.fromEnvironment('DEV_PASSWORD');
    const useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR',
        defaultValue: false);
    try {
      if (devEmail.isNotEmpty && devPassword.isNotEmpty) {
        // If DEV credentials are provided, use them.
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: devEmail,
          password: devPassword,
        );
      } else {
        // Only attempt anonymous sign-in when explicitly using emulator.
        if (!useEmulator) {
          debugPrint(
              'Skipping anonymous auto sign-in: not using emulator and no dev credentials');
          return;
        }
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      // Handle FirebaseAuth-specific errors more gracefully
      if (e is FirebaseAuthException) {
        if (e.code == 'admin-restricted-operation') {
          debugPrint(
              'Dev auto sign-in blocked by admin restriction: ${e.message}');
          return;
        }
        debugPrint('Dev auto sign-in failed: ${e.code} ${e.message}');
        return;
      }
      debugPrint('Dev auto sign-in failed: $e');
    }
    // Ensure we rebuild after the attempt so that, if the sign-in failed,
    // the UI can fall back to the normal SignInScreen instead of staying
    // on the indefinite loading indicator.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Use StreamBuilder so auth state changes are reflected live. Start a
    // timer to fall back to SignInScreen if the stream doesn't emit quickly.
    _authTimeoutTimer?.cancel();
    _authTimeoutTimer = Timer(_authStreamTimeout, () {
      if (mounted) setState(() => _authTimedOut = true);
    });

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        // If the stream has emitted, cancel the timeout timer.
        if (snap.connectionState != ConnectionState.waiting) {
          _authTimeoutTimer?.cancel();
          if (mounted && _authTimedOut) _authTimedOut = false;
        }

        final user = snap.data;

        // If waiting and we haven't timed out yet, show a loader. Also trigger
        // dev auto-signin after the first frame to avoid setState-in-build.
        if ((snap.connectionState == ConnectionState.waiting) && !_authTimedOut) {
          if (kDebugMode && !_attemptedAutoSignIn) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _tryDevAutoSignIn();
            });
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (user == null) {
          return const SignInScreen();
        }
        return HomeScreen(user: user);
      },
    );
  }

  @override
  void dispose() {
    _authTimeoutTimer?.cancel();
    super.dispose();
  }
}
