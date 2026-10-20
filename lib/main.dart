import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/provider/provider_home_screen.dart';
import 'services/notification_service.dart';
import 'utils/app_theme.dart';
import 'firebase_options.dart';

/// Set to true only on Firebase Blaze plan when Cloud Functions are deployed.
const bool kEnablePush = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // On mobile: initialise google_sign_in. On web we use signInWithPopup instead.
  if (!kIsWeb) {
    await GoogleSignIn.instance.initialize(
      clientId:
          '1049036800006-e08lfhn7gbh92dtbd471u2q367drf86m.apps.googleusercontent.com',
    );
  }

  // Firestore offline persistence enabled
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  await NotificationService.init();
  runApp(const PurrSyncApp());
}

class PurrSyncApp extends StatelessWidget {
  const PurrSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PurrSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      home: const AuthGate(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/vet_home': (context) => const ProviderHomeScreen(),
        '/clinic_home': (context) => const ProviderHomeScreen(),
        '/provider_home': (context) => const ProviderHomeScreen(),
      },
    );
  }
}
