import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import '../models/cat.dart';
import '../models/user.dart';
import '../models/user_role.dart';
import '../models/request_status.dart';
import '../models/provider_profile.dart';
import '../models/service_offering.dart';
import '../models/reservation.dart';
import '../models/booking.dart';
import '../models/announcement.dart';

/// Thrown by [FirebaseService] whenever an auth or Firestore operation
/// fails, carrying a user-friendly message safe to show in the UI.
class AppException implements Exception {
  final String message;
  AppException(this.message);
  @override
  String toString() => message;
}

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Tracks the portal selected on the LoginScreen so Pet Owners cannot log in
  /// via the Vet/Clinic Portal and Vet/Clinic Providers cannot log in via the Pet Owner Portal.
  static UserRole? selectedPortalRole;

  /// Holds AuthGate on LoginScreen while signIn / signInWithGoogle verifies the user's role
  /// against [selectedPortalRole], preventing premature dashboard navigation.
  static final ValueNotifier<bool> isVerifyingPortal = ValueNotifier<bool>(false);

  /// Stores any portal mismatch error message so LoginScreen can display it even if
  /// AuthGate triggers a sign-out.
  static String? pendingPortalError;

  // ============ AUTH ============

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'Password is too weak (use at least 6 characters).';
      case 'network-request-failed':
        return 'Network error. Check your internet connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return 'Authentication failed (${e.code}).';
    }
  }

  /// Resolves the user's profile from `users/{uid}` and automatically repairs
  /// any account that was accidentally assigned `vet`/`clinic` with an empty
  /// unconfigured `providers/{uid}` record by older Google Sign-In flows.
  Future<AppUser?> _resolveAndVerifyUserDoc(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final doc = await userRef.get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }

    var appUser = AppUser.fromMap(user.uid, doc.data() as Map<String, dynamic>);

    if (appUser.role.isProvider) {
      try {
        final providerRef = _firestore.collection('providers').doc(user.uid);
        final providerDoc = await providerRef.get();
        final pData = providerDoc.data();
        final bool isUnregisteredBlankProvider = !providerDoc.exists ||
            pData == null ||
            (((pData['address'] as String?) ?? '').trim().isEmpty &&
                ((pData['city'] as String?) ?? '').trim().isEmpty &&
                ((pData['phone'] as String?) ?? '').trim().isEmpty);

        if (isUnregisteredBlankProvider) {
          // Heal accidental Google OAuth provider creation back to Pet Owner
          await userRef.update({'role': UserRole.owner.toValue()});
          if (providerDoc.exists) {
            await providerRef.delete();
          }
          appUser = AppUser(
            id: appUser.id,
            email: appUser.email,
            fullName: appUser.fullName,
            role: UserRole.owner,
            createdAt: appUser.createdAt,
          );
        }
      } catch (_) {
        // Ignore non-fatal healing errors
      }
    }

    return appUser;
  }

  String _portalMismatchMessage({
    required UserRole expectedPortal,
    required UserRole actualRole,
  }) {
    if (expectedPortal.isProvider && !actualRole.isProvider) {
      return 'Access Denied: Your account is registered as a Pet Owner, not a Vet / Clinic Provider. Please switch to the Pet Owner Portal.';
    }
    return 'Access Denied: Your account is registered as a Vet / Clinic Provider. Please switch to the Vet / Clinic Portal.';
  }

  Future<AppUser> signUp(
    String email,
    String password,
    String fullName, {
    UserRole role = UserRole.owner,
    ProviderProfile? providerProfile,
  }) async {
    selectedPortalRole = role;
    pendingPortalError = null;
    isVerifyingPortal.value = true;
    try {
      User? user;
      try {
        UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        user = result.user;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          // If the old Firestore user doc was wiped, allow reclaiming the orphaned Auth record
          try {
            final existingCred = await _auth.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
            final existingUser = existingCred.user;
            if (existingUser != null) {
              final existingDoc = await _firestore
                  .collection('users')
                  .doc(existingUser.uid)
                  .get();
              if (!existingDoc.exists) {
                user = existingUser;
              } else {
                await _auth.signOut();
                throw AppException('An account already exists for that email.');
              }
            }
          } on FirebaseAuthException catch (_) {
            throw AppException('An account already exists for that email.');
          }
        } else {
          rethrow;
        }
      }

      if (user == null) {
        throw AppException('Registration failed. Please try again.');
      }

      final now = DateTime.now();
      AppUser appUser = AppUser(
        id: user.uid,
        email: email,
        fullName: fullName,
        role: role,
        createdAt: now,
      );

      // 1. Write users/{uid} document with permanent role
      await _firestore.collection('users').doc(user.uid).set(appUser.toMap());

      // 2. If registering as vet or clinic, create providers/{uid} document
      if (role == UserRole.vet || role == UserRole.clinic) {
        final profile = providerProfile != null
            ? ProviderProfile(
                id: user.uid,
                role: role,
                displayName: providerProfile.displayName.isNotEmpty
                    ? providerProfile.displayName
                    : fullName,
                address: providerProfile.address,
                city: providerProfile.city,
                phone: providerProfile.phone,
                bio: providerProfile.bio,
                specialty: providerProfile.specialty,
                visitTypes: providerProfile.visitTypes,
                openingHours: providerProfile.openingHours,
                openTime: providerProfile.openTime,
                closeTime: providerProfile.closeTime,
                openDays: providerProfile.openDays,
                hoursLabel: providerProfile.hoursLabel,
                active: true,
                createdAt: now,
                updatedAt: now,
              )
            : ProviderProfile(
                id: user.uid,
                role: role,
                displayName: fullName,
                address: '',
                city: '',
                phone: '',
                createdAt: now,
                updatedAt: now,
              );
        await _firestore.collection('providers').doc(user.uid).set(profile.toMap());
      }

      // Automatically send verification email on registration
      try {
        await user.sendEmailVerification();
      } catch (_) {
        // Non-blocking in case of rate limits or offline mode
      }

      return appUser;
    } on FirebaseAuthException catch (e) {
      throw AppException(_authErrorMessage(e));
    } on FirebaseException catch (e) {
      throw AppException('Could not save your profile (${e.code}). Please try again.');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Registration failed. Please try again.');
    } finally {
      isVerifyingPortal.value = false;
    }
  }

  /// Sends a verification email to the currently signed-in user if not verified.
  Future<void> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
    } on FirebaseAuthException catch (e) {
      throw AppException(_authErrorMessage(e));
    } catch (e) {
      throw AppException('Could not send verification email: $e');
    }
  }

  /// Checks if the current user has verified their email address.
  bool isEmailVerified() {
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// Reloads user data from Firebase Auth to refresh emailVerified status.
  Future<void> reloadUser() async {
    try {
      await _auth.currentUser?.reload();
    } catch (_) {}
  }

  Future<AppUser> signIn(
    String email,
    String password, {
    UserRole? expectedRole,
  }) async {
    if (expectedRole != null) {
      selectedPortalRole = expectedRole;
    }
    pendingPortalError = null;
    isVerifyingPortal.value = true;
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = result.user;
      if (user == null) {
        throw AppException('Sign in failed. Please try again.');
      }

      AppUser? appUser = await _resolveAndVerifyUserDoc(user);
      if (appUser == null) {
        // This account's Firestore user record was deleted: purge the orphaned Firebase Auth account too
        try {
          await user.delete();
        } catch (_) {}
        await _auth.signOut();
        throw AppException(
          'No account found for that email. Please use "Create Account" to register.',
        );
      }

      final portalRole = expectedRole ?? selectedPortalRole;
      if (portalRole != null && portalRole.isProvider != appUser.role.isProvider) {
        final msg = _portalMismatchMessage(
          expectedPortal: portalRole,
          actualRole: appUser.role,
        );
        pendingPortalError = msg;
        await _auth.signOut();
        throw AppException(msg);
      }

      return appUser;
    } on FirebaseAuthException catch (e) {
      throw AppException(_authErrorMessage(e));
    } on FirebaseException catch (e) {
      throw AppException('Could not load your profile (${e.code}). Please try again.');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Sign in failed: $e');
    } finally {
      isVerifyingPortal.value = false;
    }
  }

  /// Signs in or registers a user using Google OAuth.
  /// Enforces portal separation so a Pet Owner cannot sign in through the Vet/Clinic Portal
  /// and an unregistered Google account cannot bypass Vet/Clinic registration.
  Future<AppUser> signInWithGoogle({
    UserRole? expectedRole,
    bool isLoginMode = true,
    ProviderProfile? providerProfile,
    String? customFullName,
  }) async {
    if (expectedRole != null) {
      selectedPortalRole = expectedRole;
    }
    pendingPortalError = null;
    isVerifyingPortal.value = true;
    try {
      User? user;

      if (kIsWeb) {
        // Web: Firebase Auth popup — works in any browser without google_sign_in
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        final UserCredential result =
            await _auth.signInWithPopup(googleProvider);
        user = result.user;
      } else {
        // Mobile: use google_sign_in package
        final GoogleSignInAccount googleUser =
            await GoogleSignIn.instance.authenticate();
        final GoogleSignInAuthentication googleAuth =
            googleUser.authentication;
        final OAuthCredential credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );
        final UserCredential result =
            await _auth.signInWithCredential(credential);
        user = result.user;
      }

      if (user == null) {
        throw AppException('Google sign-in failed. Please try again.');
      }

      final portalRole = expectedRole ?? selectedPortalRole ?? UserRole.owner;
      final existingUser = await _resolveAndVerifyUserDoc(user);

      if (existingUser != null) {
        // Returning user: strictly verify their registered role matches the selected portal
        if (portalRole.isProvider != existingUser.role.isProvider) {
          final msg = _portalMismatchMessage(
            expectedPortal: portalRole,
            actualRole: existingUser.role,
          );
          pendingPortalError = msg;
          await _auth.signOut();
          throw AppException(msg);
        }
        return existingUser;
      }

      // Brand-new Google user (no users/{uid} document yet):
      if (portalRole.isProvider) {
        // Do NOT allow a random Google account to silently create a Vet/Clinic account on Sign In
        if (isLoginMode || providerProfile == null) {
          const msg =
              'Access Denied: No Vet / Clinic Provider account found for this Google account. Please use "Create Account" to register your clinic details, or switch to the Pet Owner Portal.';
          pendingPortalError = msg;
          await _auth.signOut();
          throw AppException(msg);
        }
      }

      final now = DateTime.now();
      final resolvedName = (customFullName != null && customFullName.trim().isNotEmpty)
          ? customFullName.trim()
          : (user.displayName ?? (user.email?.split('@').first ?? 'Cat Parent'));

      final appUser = AppUser(
        id: user.uid,
        email: user.email ?? '',
        fullName: resolvedName,
        role: portalRole,
        createdAt: now,
      );
      await _firestore.collection('users').doc(user.uid).set(appUser.toMap());

      if (portalRole.isProvider && providerProfile != null) {
        final pProfile = ProviderProfile(
          id: user.uid,
          role: portalRole,
          displayName: providerProfile.displayName.isNotEmpty
              ? providerProfile.displayName
              : resolvedName,
          address: providerProfile.address,
          city: providerProfile.city,
          phone: providerProfile.phone,
          bio: providerProfile.bio,
          specialty: providerProfile.specialty,
          visitTypes: providerProfile.visitTypes,
          openTime: providerProfile.openTime,
          closeTime: providerProfile.closeTime,
          openDays: providerProfile.openDays,
          hoursLabel: providerProfile.hoursLabel,
          active: true,
          createdAt: now,
          updatedAt: now,
        );
        await _firestore
            .collection('providers')
            .doc(user.uid)
            .set(pProfile.toMap(), SetOptions(merge: true));
      }

      return appUser;
    } on FirebaseAuthException catch (e) {
      throw AppException(_authErrorMessage(e));
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Google sign-in error: $e');
    } finally {
      isVerifyingPortal.value = false;
    }
  }

  Future<void> signOut() async {
    selectedPortalRole = null;
    isVerifyingPortal.value = false;
    // Always sign out from Firebase Auth FIRST so UI immediately transitions to LoginScreen.
    // On Web, GoogleSignIn.instance is not initialized and calling it hangs forever.
    await _auth.signOut();
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance
            .signOut()
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  User? getCurrentUser() {
    return _auth.currentUser;
  }

  Future<UserRole> getMyRole() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return UserRole.owner;

      final appUser = await _resolveAndVerifyUserDoc(user);
      if (appUser == null) {
        // User document in Firestore was deleted: purge the active Firebase Auth session & user
        try {
          await user.delete();
        } catch (_) {}
        await signOut();
        return UserRole.owner;
      }
      final actualRole = appUser.role;

      if (selectedPortalRole != null &&
          selectedPortalRole!.isProvider != actualRole.isProvider) {
        final msg = _portalMismatchMessage(
          expectedPortal: selectedPortalRole!,
          actualRole: actualRole,
        );
        pendingPortalError = msg;
        await signOut();
        throw AppException(msg);
      }

      return actualRole;
    } on FirebaseException catch (e) {
      throw AppException('Could not verify user role (${e.code}). Check your connection.');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Failed to determine user role.');
    }
  }

  Future<AppUser?> getCurrentAppUser() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;
      return await _resolveAndVerifyUserDoc(user);
    } on FirebaseException catch (e) {
      throw AppException('Could not load user data (${e.code}).');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Failed to load user profile.');
    }
  }

  // ============ PROVIDERS ============

  Future<ProviderProfile?> getProviderProfile(String uid) async {
    try {
      final doc = await _firestore.collection('providers').doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      return ProviderProfile.fromMap(doc.id, doc.data() as Map<String, dynamic>);
    } on FirebaseException catch (e) {
      throw AppException('Could not load provider profile (${e.code}).');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Failed to load provider profile.');
    }
  }

  Future<void> saveProviderProfile(ProviderProfile profile) async {
    try {
      await _firestore.collection('providers').doc(profile.id).set(
            profile.toMap(),
            SetOptions(merge: true),
          );
    } on FirebaseException catch (e) {
      throw AppException('Could not save provider profile (${e.code}).');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Failed to save provider profile.');
    }
  }

  Stream<List<ProviderProfile>> getProviders(UserRole role) {
    return _firestore
        .collection('providers')
        .where('role', isEqualTo: role.toValue())
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return ProviderProfile.fromMap(doc.id, doc.data());
      }).toList();
    }).handleError((e) {
      throw AppException('Could not load providers. Check your connection.');
    });
  }

  /// Streams all registered providers (both vets and clinics) for the unified directory.
  Stream<List<ProviderProfile>> getAllProviders() {
    return _firestore
        .collection('providers')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return ProviderProfile.fromMap(doc.id, doc.data());
      }).toList();
    }).handleError((e) {
      throw AppException('Could not load providers. Check your connection.');
    });
  }

  // ============ CATS ============

  Future<String> addCat(Cat cat) async {
    try {
      final docRef = cat.id.isNotEmpty
          ? _firestore.collection('cats').doc(cat.id)
          : _firestore.collection('cats').doc();
      cat.id = docRef.id;
      await docRef.set(cat.toMap());
      return docRef.id;
    } on FirebaseException catch (e) {
      throw AppException('Could not save cat profile (${e.code}). Please try again.');
    } catch (e) {
      throw AppException('Error saving cat: $e');
    }
  }

  Future<void> updateCat(Cat cat) async {
    try {
      await _firestore.collection('cats').doc(cat.id).update(cat.toUpdateMap());
    } on FirebaseException catch (e) {
      throw AppException('Could not update cat profile (${e.code}). Please try again.');
    } catch (e) {
      throw AppException('Error updating cat: $e');
    }
  }

  /// Deletes a cat and cleans up its child records (weight_logs, vaccines, vet_visits)
  /// so orphan records never violate parent-cat lookup rules.
  Future<void> deleteCat(String catId) async {
    try {
      // 1. Delete associated weight logs
      final weightDocs = await _firestore.collection('weight_logs').where('catId', isEqualTo: catId).get();
      for (final doc in weightDocs.docs) {
        await doc.reference.delete();
      }

      // 2. Delete associated vaccines
      final vaccineDocs = await _firestore.collection('vaccines').where('catId', isEqualTo: catId).get();
      for (final doc in vaccineDocs.docs) {
        await doc.reference.delete();
      }

      // 3. Delete associated vet visits
      final visitDocs = await _firestore.collection('vet_visits').where('catId', isEqualTo: catId).get();
      for (final doc in visitDocs.docs) {
        await doc.reference.delete();
      }

      // 4. Delete the cat document
      await _firestore.collection('cats').doc(catId).delete();
    } on FirebaseException catch (e) {
      throw AppException('Could not delete cat profile (${e.code}). Please try again.');
    } catch (e) {
      throw AppException('Error deleting cat: $e');
    }
  }

  Stream<List<Cat>> getCats(String userId) {
    return _firestore
        .collection('cats')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Cat.fromMap(doc.id, doc.data());
      }).toList();
    }).handleError((e) {
      throw AppException('Could not load your cats. Check your connection and try again.');
    });
  }

  // ============ VACCINES ============

  /// Duplicate check: blocks duplicate record for same cat, same vaccine type, on the same calendar day.
  Future<bool> hasDuplicateVaccineOnDate(
    String catId,
    String type,
    DateTime date, {
    String? excludeRecordId,
  }) async {
    try {
      final snapshot = await _firestore.collection('vaccines').where('catId', isEqualTo: catId).get();
      final targetType = type.trim().toLowerCase();
      for (final doc in snapshot.docs) {
        if (excludeRecordId != null && doc.id == excludeRecordId) continue;
        final data = doc.data();
        final existingType = (data['type'] ?? '').toString().trim().toLowerCase();
        final dateGivenVal = data['dateGiven'];
        DateTime? existingDate;
        if (dateGivenVal is Timestamp) existingDate = dateGivenVal.toDate();
        if (dateGivenVal is DateTime) existingDate = dateGivenVal;

        if (existingDate != null &&
            existingType == targetType &&
            existingDate.year == date.year &&
            existingDate.month == date.month &&
            existingDate.day == date.day) {
          return true;
        }
      }
      return false;
    } on FirebaseException catch (e) {
      throw AppException('Error checking duplicate vaccine (${e.code}).');
    } catch (e) {
      throw AppException('Error checking duplicate vaccine: $e');
    }
  }

  Future<String> addVaccine(VaccineRecord vaccine) async {
    try {
      final isDup = await hasDuplicateVaccineOnDate(vaccine.catId, vaccine.type, vaccine.dateGiven);
      if (isDup) {
        final formattedDate = vaccine.dateGiven.toLocal().toString().split(' ')[0];
        throw AppException(
          'A ${vaccine.type} record already exists for $formattedDate. Pick a different date or edit the existing record instead.',
        );
      }

      final docRef = vaccine.id.isNotEmpty
          ? _firestore.collection('vaccines').doc(vaccine.id)
          : _firestore.collection('vaccines').doc();
      vaccine.id = docRef.id;
      await docRef.set(vaccine.toMap());
      return docRef.id;
    } on FirebaseException catch (e) {
      throw AppException('Could not save vaccine record (${e.code}). Please try again.');
    }
  }

  Future<void> updateVaccineRecord(VaccineRecord vaccine) async {
    try {
      final isDup = await hasDuplicateVaccineOnDate(
        vaccine.catId,
        vaccine.type,
        vaccine.dateGiven,
        excludeRecordId: vaccine.id,
      );
      if (isDup) {
        final formattedDate = vaccine.dateGiven.toLocal().toString().split(' ')[0];
        throw AppException(
          'A ${vaccine.type} record already exists for $formattedDate. Pick a different date or edit the existing record instead.',
        );
      }
      await _firestore.collection('vaccines').doc(vaccine.id).update(vaccine.toMap());
    } on FirebaseException catch (e) {
      throw AppException('Could not update vaccine record (${e.code}).');
    }
  }

  Future<void> deleteVaccineRecord(String vaccineId) async {
    try {
      await _firestore.collection('vaccines').doc(vaccineId).delete();
    } on FirebaseException catch (e) {
      throw AppException('Could not delete vaccine record (${e.code}).');
    }
  }

  Stream<List<VaccineRecord>> getVaccines(String catId) {
    return _firestore
        .collection('vaccines')
        .where('catId', isEqualTo: catId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        DateTime parseD(dynamic v) => (v is Timestamp) ? v.toDate() : (v is DateTime ? v : DateTime.now());
        return VaccineRecord(
          id: doc.id,
          catId: data['catId'] ?? '',
          type: data['type'] ?? '',
          dateGiven: parseD(data['dateGiven']),
          nextDueDate: parseD(data['nextDueDate']),
          clinicName: data['clinicName'],
          veterinarian: data['veterinarian'],
          notes: data['notes'],
        );
      }).toList();
      list.sort((a, b) => b.dateGiven.compareTo(a.dateGiven));
      return list;
    });
  }

  // ============ WEIGHT LOGS ============

  Future<String> addWeightLog(WeightLog log) async {
    try {
      final docRef = log.id.isNotEmpty
          ? _firestore.collection('weight_logs').doc(log.id)
          : _firestore.collection('weight_logs').doc();
      log.id = docRef.id;
      await docRef.set(log.toMap());
      return docRef.id;
    } on FirebaseException catch (e) {
      throw AppException('Could not save weight log (${e.code}). Please try again.');
    }
  }

  Future<void> updateWeightLog(WeightLog log) async {
    try {
      await _firestore.collection('weight_logs').doc(log.id).update(log.toMap());
    } on FirebaseException catch (e) {
      throw AppException('Could not update weight log (${e.code}).');
    }
  }

  Future<void> deleteWeightLog(String logId) async {
    try {
      await _firestore.collection('weight_logs').doc(logId).delete();
    } on FirebaseException catch (e) {
      throw AppException('Could not delete weight log (${e.code}).');
    }
  }

  Stream<List<WeightLog>> getWeightLogs(String catId) {
    return _firestore
        .collection('weight_logs')
        .where('catId', isEqualTo: catId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        DateTime parseD(dynamic v) => (v is Timestamp) ? v.toDate() : (v is DateTime ? v : DateTime.now());
        return WeightLog(
          id: doc.id,
          catId: data['catId'] ?? '',
          weight: (data['weight'] ?? 0).toDouble(),
          date: parseD(data['date']),
          notes: data['notes'],
        );
      }).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  // ============ VET VISITS ============

  Future<String> addVetVisit(VetVisit visit) async {
    try {
      final docRef = visit.id.isNotEmpty
          ? _firestore.collection('vet_visits').doc(visit.id)
          : _firestore.collection('vet_visits').doc();
      visit.id = docRef.id;
      await docRef.set(visit.toMap());
      return docRef.id;
    } on FirebaseException catch (e) {
      throw AppException('Could not save vet visit (${e.code}). Please try again.');
    }
  }

  Future<void> updateVetVisit(VetVisit visit) async {
    try {
      await _firestore.collection('vet_visits').doc(visit.id).update(visit.toMap());
    } on FirebaseException catch (e) {
      throw AppException('Could not update vet visit (${e.code}).');
    }
  }

  Future<void> deleteVetVisit(String visitId) async {
    try {
      await _firestore.collection('vet_visits').doc(visitId).delete();
    } on FirebaseException catch (e) {
      throw AppException('Could not delete vet visit (${e.code}).');
    }
  }

  Stream<List<VetVisit>> getVetVisits(String catId) {
    return _firestore
        .collection('vet_visits')
        .where('catId', isEqualTo: catId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        DateTime parseD(dynamic v) => (v is Timestamp) ? v.toDate() : (v is DateTime ? v : DateTime.now());
        return VetVisit(
          id: doc.id,
          catId: data['catId'] ?? '',
          visitDate: parseD(data['visitDate']),
          clinicName: data['clinicName'] ?? '',
          reason: data['reason'] ?? '',
          diagnosis: data['diagnosis'] ?? '',
          prescribedMedicine: data['prescribedMedicine'],
          followUpDate: data['followUpDate'] != null ? parseD(data['followUpDate']) : null,
        );
      }).toList();
      list.sort((a, b) => b.visitDate.compareTo(a.visitDate));
      return list;
    });
  }

  // ============ CLINIC SERVICES ============

  Future<String> addService(ServiceOffering service) async {
    try {
      final docRef = service.id.isNotEmpty
          ? _firestore.collection('services').doc(service.id)
          : _firestore.collection('services').doc();
      final newService = ServiceOffering(
        id: docRef.id,
        providerId: service.providerId,
        providerName: service.providerName,
        name: service.name,
        description: service.description,
        category: service.category,
        price: service.price,
        durationMinutes: service.durationMinutes,
        active: service.active,
        createdAt: service.createdAt,
        updatedAt: DateTime.now(),
      );
      await docRef.set(newService.toMap());
      return docRef.id;
    } on FirebaseException catch (e) {
      throw AppException('Could not add service (${e.code}). Please try again.');
    } catch (e) {
      throw AppException('Error adding service: $e');
    }
  }

  Future<void> updateService(ServiceOffering service) async {
    try {
      await _firestore.collection('services').doc(service.id).update(service.toUpdateMap());
    } on FirebaseException catch (e) {
      throw AppException('Could not update service (${e.code}).');
    } catch (e) {
      throw AppException('Error updating service: $e');
    }
  }

  Future<void> deleteService(String serviceId) async {
    try {
      await _firestore.collection('services').doc(serviceId).delete();
    } on FirebaseException catch (e) {
      throw AppException('Could not delete service (${e.code}).');
    } catch (e) {
      throw AppException('Error deleting service: $e');
    }
  }

  Stream<List<ServiceOffering>> getClinicServices(String clinicId) {
    return _firestore
        .collection('services')
        .where('providerId', isEqualTo: clinicId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => ServiceOffering.fromMap(doc.id, doc.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  // ============ RESERVATIONS (OWNER <-> VET) ============

  Future<String> createReservation(Reservation reservation) async {
    try {
      // Duplicate block: check if owner already has a pending or accepted reservation
      // for same cat, same vet, and same requestedAt. Filter by ownerId, match in Dart.
      final existingDocs = await _firestore
          .collection('reservations')
          .where('ownerId', isEqualTo: reservation.ownerId)
          .get();

      for (final doc in existingDocs.docs) {
        final existing = Reservation.fromMap(doc.id, doc.data());
        if ((existing.status == RequestStatus.pending || existing.status == RequestStatus.accepted) &&
            existing.catId == reservation.catId &&
            existing.vetId == reservation.vetId &&
            existing.requestedAt.year == reservation.requestedAt.year &&
            existing.requestedAt.month == reservation.requestedAt.month &&
            existing.requestedAt.day == reservation.requestedAt.day &&
            existing.requestedAt.hour == reservation.requestedAt.hour &&
            existing.requestedAt.minute == reservation.requestedAt.minute) {
          throw AppException('You already have a pending or accepted reservation for this cat and vet at that time.');
        }
      }

      final docRef = _firestore.collection('reservations').doc();
      final toSave = Reservation(
        id: docRef.id,
        ownerId: reservation.ownerId,
        ownerName: reservation.ownerName,
        catId: reservation.catId,
        catName: reservation.catName,
        catBreed: reservation.catBreed,
        vetId: reservation.vetId,
        vetName: reservation.vetName,
        visitType: reservation.visitType,
        requestedAt: reservation.requestedAt,
        notes: reservation.notes,
        status: RequestStatus.pending,
        providerNote: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await docRef.set(toSave.toMap());
      return docRef.id;
    } on FirebaseException catch (e) {
      throw AppException('Could not create reservation (${e.code}). Please try again.');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Error creating reservation: $e');
    }
  }

  Future<void> updateReservationDetails(String id, {required String visitType, required DateTime requestedAt, required String notes}) async {
    try {
      await _firestore.collection('reservations').doc(id).update({
        'visitType': visitType,
        'requestedAt': Timestamp.fromDate(requestedAt),
        'notes': notes,
        'updatedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw AppException('Could not update reservation (${e.code}).');
    }
  }

  Future<void> cancelReservation(String id) async {
    try {
      await _firestore.collection('reservations').doc(id).update({
        'status': RequestStatus.cancelled.toValue(),
        'updatedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw AppException('Could not cancel reservation (${e.code}).');
    }
  }

  Future<void> deleteReservation(String id) async {
    try {
      await _firestore.collection('reservations').doc(id).delete();
    } on FirebaseException catch (e) {
      throw AppException('Could not delete reservation (${e.code}).');
    }
  }

  Future<void> respondToReservation(String id, RequestStatus newStatus, {String? providerNote}) async {
    try {
      await _firestore.collection('reservations').doc(id).update({
        'status': newStatus.toValue(),
        'providerNote': providerNote,
        'updatedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw AppException('Could not update reservation status (${e.code}).');
    }
  }

  Stream<List<Reservation>> getOwnerReservations(String ownerId) {
    return _firestore
        .collection('reservations')
        .where('ownerId', isEqualTo: ownerId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => Reservation.fromMap(doc.id, doc.data())).toList();
      list.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
      return list;
    });
  }

  Stream<List<Reservation>> getVetReservations(String vetId) {
    return _firestore
        .collection('reservations')
        .where('vetId', isEqualTo: vetId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => Reservation.fromMap(doc.id, doc.data())).toList();
      list.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
      return list;
    });
  }

  // ============ BOOKINGS (OWNER <-> CLINIC) ============

  Future<String> createBooking(Booking booking) async {
    try {
      // Duplicate block: check if owner already has a pending or accepted booking
      // for same cat, same clinic, same service, and same scheduledAt.
      final existingDocs = await _firestore
          .collection('bookings')
          .where('ownerId', isEqualTo: booking.ownerId)
          .get();

      for (final doc in existingDocs.docs) {
        final existing = Booking.fromMap(doc.id, doc.data());
        if ((existing.status == RequestStatus.pending || existing.status == RequestStatus.accepted) &&
            existing.catId == booking.catId &&
            existing.clinicId == booking.clinicId &&
            existing.serviceId == booking.serviceId &&
            existing.scheduledAt.year == booking.scheduledAt.year &&
            existing.scheduledAt.month == booking.scheduledAt.month &&
            existing.scheduledAt.day == booking.scheduledAt.day &&
            existing.scheduledAt.hour == booking.scheduledAt.hour &&
            existing.scheduledAt.minute == booking.scheduledAt.minute) {
          throw AppException('You already have a pending or accepted booking for this cat and service at that time.');
        }
      }

      final docRef = _firestore.collection('bookings').doc();
      final toSave = Booking(
        id: docRef.id,
        ownerId: booking.ownerId,
        ownerName: booking.ownerName,
        catId: booking.catId,
        catName: booking.catName,
        catBreed: booking.catBreed,
        clinicId: booking.clinicId,
        clinicName: booking.clinicName,
        serviceId: booking.serviceId,
        serviceName: booking.serviceName,
        servicePrice: booking.servicePrice,
        serviceDurationMinutes: booking.serviceDurationMinutes,
        scheduledAt: booking.scheduledAt,
        notes: booking.notes,
        status: RequestStatus.pending,
        providerNote: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await docRef.set(toSave.toMap());
      return docRef.id;
    } on FirebaseException catch (e) {
      throw AppException('Could not create booking (${e.code}). Please try again.');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Error creating booking: $e');
    }
  }

  Future<void> updateBookingDetails(
    String id, {
    required String serviceId,
    required String serviceName,
    required double servicePrice,
    required int serviceDurationMinutes,
    required DateTime scheduledAt,
    required String notes,
  }) async {
    try {
      await _firestore.collection('bookings').doc(id).update({
        'serviceId': serviceId,
        'serviceName': serviceName,
        'servicePrice': servicePrice,
        'serviceDurationMinutes': serviceDurationMinutes,
        'scheduledAt': Timestamp.fromDate(scheduledAt),
        'notes': notes,
        'updatedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw AppException('Could not update booking (${e.code}).');
    }
  }

  Future<void> cancelBooking(String id) async {
    try {
      await _firestore.collection('bookings').doc(id).update({
        'status': RequestStatus.cancelled.toValue(),
        'updatedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw AppException('Could not cancel booking (${e.code}).');
    }
  }

  Future<void> deleteBooking(String id) async {
    try {
      await _firestore.collection('bookings').doc(id).delete();
    } on FirebaseException catch (e) {
      throw AppException('Could not delete booking (${e.code}).');
    }
  }

  Future<void> respondToBooking(String id, RequestStatus newStatus, {String? providerNote}) async {
    try {
      await _firestore.collection('bookings').doc(id).update({
        'status': newStatus.toValue(),
        'providerNote': providerNote,
        'updatedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      throw AppException('Could not update booking status (${e.code}).');
    }
  }

  Stream<List<Booking>> getOwnerBookings(String ownerId) {
    return _firestore
        .collection('bookings')
        .where('ownerId', isEqualTo: ownerId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => Booking.fromMap(doc.id, doc.data())).toList();
      list.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
      return list;
    });
  }

  Stream<List<Booking>> getClinicBookings(String clinicId) {
    return _firestore
        .collection('bookings')
        .where('clinicId', isEqualTo: clinicId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => Booking.fromMap(doc.id, doc.data())).toList();
      list.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
      return list;
    });
  }

  /// Returns all accepted slot ranges (reservations and bookings) for a provider on a given date.
  Future<List<Map<String, dynamic>>> getAcceptedSlotsForProvider(String providerId, DateTime date) async {
    try {
      final List<Map<String, dynamic>> slots = [];
      final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      // 1. Accepted reservations
      final resDocs = await _firestore
          .collection('reservations')
          .where('vetId', isEqualTo: providerId)
          .where('status', isEqualTo: RequestStatus.accepted.toValue())
          .get();

      for (final doc in resDocs.docs) {
        final res = Reservation.fromMap(doc.id, doc.data());
        if (res.requestedAt.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
            res.requestedAt.isBefore(endOfDay.add(const Duration(seconds: 1)))) {
          final end = res.requestedAt.add(const Duration(minutes: 30));
          slots.add({
            'id': res.id,
            'type': 'reservation',
            'start': res.requestedAt,
            'end': end,
            'label': '${res.visitType} (${res.catName})',
          });
        }
      }

      // 2. Accepted bookings
      final bookDocs = await _firestore
          .collection('bookings')
          .where('clinicId', isEqualTo: providerId)
          .where('status', isEqualTo: RequestStatus.accepted.toValue())
          .get();

      for (final doc in bookDocs.docs) {
        final b = Booking.fromMap(doc.id, doc.data());
        if (b.scheduledAt.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
            b.scheduledAt.isBefore(endOfDay.add(const Duration(seconds: 1)))) {
          final end = b.scheduledAt.add(Duration(minutes: b.serviceDurationMinutes));
          slots.add({
            'id': b.id,
            'type': 'booking',
            'start': b.scheduledAt,
            'end': end,
            'label': '${b.serviceName} (${b.catName})',
          });
        }
      }

      slots.sort((a, b) => (a['start'] as DateTime).compareTo(b['start'] as DateTime));
      return slots;
    } catch (_) {
      return [];
    }
  }

  /// Checks whether a proposed appointment slot overlaps with any already accepted reservation or booking.
  Future<bool> isProviderSlotOccupied(
    String providerId,
    DateTime requestedStart,
    int durationMinutes, {
    String? excludeId,
  }) async {
    final requestedEnd = requestedStart.add(Duration(minutes: durationMinutes));
    final slots = await getAcceptedSlotsForProvider(providerId, requestedStart);
    for (final s in slots) {
      if (excludeId != null && s['id'] == excludeId) continue;
      final slotStart = s['start'] as DateTime;
      final slotEnd = s['end'] as DateTime;
      if (requestedStart.isBefore(slotEnd) && requestedEnd.isAfter(slotStart)) {
        return true;
      }
    }
    return false;
  }

  // ============ ANNOUNCEMENTS ============

  Future<String> addAnnouncement(Announcement item) async {
    try {
      final docRef = item.id.isNotEmpty
          ? _firestore.collection('announcements').doc(item.id)
          : _firestore.collection('announcements').doc();
      final toSave = Announcement(
        id: docRef.id,
        authorId: item.authorId,
        authorRole: item.authorRole,
        authorName: item.authorName,
        type: item.type,
        title: item.title,
        body: item.body,
        eventDate: item.eventDate,
        location: item.location,
        published: item.published,
        createdAt: item.createdAt,
        updatedAt: DateTime.now(),
      );
      await docRef.set(toSave.toMap());
      return docRef.id;
    } on FirebaseException catch (e) {
      throw AppException('Could not save announcement (${e.code}). Please try again.');
    } catch (e) {
      throw AppException('Error saving announcement: $e');
    }
  }

  Future<String> createAnnouncement(Announcement item) => addAnnouncement(item);

  Future<void> updateAnnouncement(Announcement item) async {
    try {
      await _firestore.collection('announcements').doc(item.id).update(item.toUpdateMap());
    } on FirebaseException catch (e) {
      throw AppException('Could not update announcement (${e.code}).');
    } catch (e) {
      throw AppException('Error updating announcement: $e');
    }
  }

  Future<void> deleteAnnouncement(String id) async {
    try {
      await _firestore.collection('announcements').doc(id).delete();
    } on FirebaseException catch (e) {
      throw AppException('Could not delete announcement (${e.code}).');
    } catch (e) {
      throw AppException('Error deleting announcement: $e');
    }
  }

  Stream<List<Announcement>> getPublishedAnnouncements() {
    return _firestore
        .collection('announcements')
        .where('published', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => Announcement.fromMap(doc.id, doc.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Stream<List<Announcement>> getMyAnnouncements(String authorId) {
    return _firestore
        .collection('announcements')
        .where('authorId', isEqualTo: authorId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => Announcement.fromMap(doc.id, doc.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }
}
