import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user_role.dart';
import '../../services/firebase_service.dart';
import '../../widgets/boutique_animations.dart';
import 'login_screen.dart';
import '../home_screen.dart';
import '../provider/provider_home_screen.dart';

/// Central authentication routing gate.
/// Listens to [FirebaseAuth.instance.authStateChanges()].
/// Automatically routes the user to their role-specific home screen
/// without requiring manual page redirects.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final FirebaseService _authService = FirebaseService();
  Key _roleFutureKey = UniqueKey();

  void _retryRoleFetch() {
    setState(() {
      _roleFutureKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: FirebaseService.isVerifyingPortal,
      builder: (context, isVerifying, _) {
        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            // While Firebase Auth is establishing initial state
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const _SplashLoadingScreen(message: 'Initializing PurrSync...');
            }

            final User? user = authSnapshot.data;

            // If not logged in or currently verifying portal role -> keep LoginScreen mounted
            if (user == null || isVerifying) {
              return const LoginScreen();
            }

            // Signed in -> determine role from users/{uid}
            return FutureBuilder<UserRole>(
              key: _roleFutureKey,
              future: _authService.getMyRole(),
              builder: (context, roleSnapshot) {
                if (roleSnapshot.connectionState == ConnectionState.waiting) {
                  return const _SplashLoadingScreen(message: 'Loading your profile...');
                }

                if (roleSnapshot.hasError) {
                  // If getMyRole threw a portal mismatch error, sign out & return to LoginScreen
                  if (FirebaseService.pendingPortalError != null) {
                    return const LoginScreen();
                  }
                  return Scaffold(
                    body: SafeArea(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cloud_off, size: 64, color: Colors.orange),
                              const SizedBox(height: 16),
                              const Text(
                                'Unable to load profile',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${roleSnapshot.error}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: _retryRoleFetch,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () => _authService.signOut(),
                                child: const Text('Back to Login'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final role = roleSnapshot.data ?? UserRole.owner;

                // Secondary safety guard: ensure portal selection matches actual role
                final expectedPortal = FirebaseService.selectedPortalRole;
                if (expectedPortal != null && expectedPortal.isProvider != role.isProvider) {
                  FirebaseService.pendingPortalError = expectedPortal.isProvider
                      ? 'Access Denied: Your account is registered as a Pet Owner, not a Vet / Clinic Provider. Please switch to the Pet Owner Portal.'
                      : 'Access Denied: Your account is registered as a Vet / Clinic Provider. Please switch to the Vet / Clinic Portal.';
                  Future.microtask(() => _authService.signOut());
                  return const LoginScreen();
                }

                switch (role) {
                  case UserRole.vet:
                  case UserRole.clinic:
                    return const ProviderHomeScreen();
                  case UserRole.owner:
                    return const HomeScreen();
                }
              },
            );
          },
        );
      },
    );
  }
}

class _SplashLoadingScreen extends StatelessWidget {
  final String message;
  const _SplashLoadingScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return AnimatedPawHeartbeatSplash(message: message);
  }
}
