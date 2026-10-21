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

  // ============ AUTOMATED CLINICAL EMR & QR CHECK-IN ============

  /// Fetches a single Cat document by ID (for Vet Smart EMR baseline lookup).
  Future<Cat?> getCatById(String catId) async {
    try {
      final doc = await _firestore.collection('cats').doc(catId).get();
      if (!doc.exists || doc.data() == null) return null;
      return Cat.fromMap(doc.id, doc.data()!);
    } catch (_) {
      return null;
    }
  }

  /// Automatically processes all pending Reservations and Bookings for a clinic/vet:
  /// - Checks for time slot conflicts (`isProviderSlotOccupied`)
  /// - Automatically accepts non-conflicting slots (and all Emergency Triage requests)
  /// - Automatically assigns sequential Queue Numbers (`Q-01`, `Q-02`, ...)
  Future<Map<String, int>> autoProcessPendingAppointments({
    required String providerId,
    required String providerName,
  }) async {
    int acceptedCount = 0;
    int conflictCount = 0;
    try {
      final resSnap = await _firestore
          .collection('reservations')
          .where('vetId', isEqualTo: providerId)
          .get();
      final bookSnap = await _firestore
          .collection('bookings')
          .where('clinicId', isEqualTo: providerId)
          .get();

      final now = DateTime.now();
      int seq = 1;

      for (final doc in resSnap.docs) {
        final r = Reservation.fromMap(doc.id, doc.data());
        if (r.status != RequestStatus.pending) continue;
        final isEmergency = r.visitType.toLowerCase().contains('emergency');
        if (!isEmergency && r.requestedAt.isBefore(now)) continue;

        final occupied = isEmergency
            ? false
            : await isProviderSlotOccupied(
                providerId,
                r.requestedAt,
                30,
                excludeId: r.id,
              );

        if (occupied) {
          conflictCount++;
          continue;
        }

        final catInitial = r.catName.isNotEmpty ? r.catName[0].toUpperCase() : 'C';
        final queueNum = isEmergency
            ? 'Q-00-EMG'
            : 'Q-${seq.toString().padLeft(2, '0')}-$catInitial';
        seq++;

        await _firestore.collection('reservations').doc(r.id).update({
          'status': RequestStatus.accepted.toValue(),
          'queueNumber': queueNum,
          'providerNote': isEmergency
              ? '🚨 Auto-Accepted Priority Emergency Triage ($queueNum). Proceed immediately.'
              : '⚡ Auto-Confirmed by $providerName Smart Queue ($queueNum).',
          'updatedAt': Timestamp.now(),
        });
        acceptedCount++;
      }

      for (final doc in bookSnap.docs) {
        final b = Booking.fromMap(doc.id, doc.data());
        if (b.status != RequestStatus.pending) continue;
        final isEmergency = b.serviceName.toLowerCase().contains('emergency');
        if (!isEmergency && b.scheduledAt.isBefore(now)) continue;

        final occupied = isEmergency
            ? false
            : await isProviderSlotOccupied(
                providerId,
                b.scheduledAt,
                b.serviceDurationMinutes,
                excludeId: b.id,
              );

        if (occupied) {
          conflictCount++;
          continue;
        }

        final catInitial = b.catName.isNotEmpty ? b.catName[0].toUpperCase() : 'C';
        final queueNum = isEmergency
            ? 'Q-00-EMG'
            : 'Q-${seq.toString().padLeft(2, '0')}-$catInitial';
        seq++;

        await _firestore.collection('bookings').doc(b.id).update({
          'status': RequestStatus.accepted.toValue(),
          'queueNumber': queueNum,
          'providerNote': '⚡ Auto-Confirmed by $providerName Smart Queue ($queueNum).',
          'updatedAt': Timestamp.now(),
        });
        acceptedCount++;
      }

      return {
        'acceptedCount': acceptedCount,
        'conflictCount': conflictCount,
      };
    } catch (e) {
      throw AppException('Auto-queue processing failed: $e');
    }
  }

  /// Automatically populates a complete standard feline veterinary service catalog
  /// for a clinic/vet in 1 tap (skipping any service names that already exist).
  Future<int> autoSeedStandardClinicServices({
    required String providerId,
    required String providerName,
  }) async {
    final existingSnap = await _firestore
        .collection('services')
        .where('providerId', isEqualTo: providerId)
        .get();
    final existingNames = existingSnap.docs
        .map((d) => (d.data()['name'] ?? '').toString().trim().toLowerCase())
        .toSet();

    final standardCatalog = <Map<String, dynamic>>[
      {
        'name': 'Comprehensive Feline Wellness Check-Up',
        'category': 'Consultation',
        'price': 550.0,
        'durationMinutes': 30,
        'description': 'Full nose-to-tail physical exam, weight & temperature check, cardiopulmonary auscultation, and nutritional consult.',
      },
      {
        'name': '4-in-1 Core Feline Vaccine (FVRCP)',
        'category': 'Vaccination',
        'price': 850.0,
        'durationMinutes': 20,
        'description': 'Core protection against Feline Viral Rhinotracheitis, Calicivirus, Panleukopenia, and Chlamydia with auto-booster tracking.',
      },
      {
        'name': 'Anti-Rabies Core Vaccine & Deworming',
        'category': 'Vaccination',
        'price': 450.0,
        'durationMinutes': 20,
        'description': 'Rabies immunization plus weight-calibrated broad-spectrum feline oral deworming.',
      },
      {
        'name': 'Feline Kapon (Spay / Neuter Surgery Package)',
        'category': 'Surgery',
        'price': 1800.0,
        'durationMinutes': 60,
        'description': 'Sterile surgical sterilization with pre-anesthetic vitals check, post-op pain relief (Meloxicam), and long-acting antibiotic.',
      },
      {
        'name': 'CBC Blood Chemistry & FIV/FeLV Snap Test',
        'category': 'Consultation',
        'price': 1450.0,
        'durationMinutes': 30,
        'description': 'In-house automated Hematology CBC panel and rapid Feline Immunodeficiency / Leukemia virus screening.',
      },
      {
        'name': 'Ultrasonic Feline Dental Scaling & Polishing',
        'category': 'Dental',
        'price': 2200.0,
        'durationMinutes': 60,
        'description': 'Tartar removal, gingival pocket cleaning, and oral antiseptic flush under monitored sedation.',
      },
      {
        'name': 'Medicated Feline Spa, Anti-Flea Bath & Sanitary Trim',
        'category': 'Grooming',
        'price': 650.0,
        'durationMinutes': 45,
        'description': 'Cat-safe warm hydro-bath, ear cleaning, nail clipping, paw pad trim, and blow-dry.',
      },
    ];

    int addedCount = 0;
    final now = DateTime.now();
    for (final item in standardCatalog) {
      final name = item['name'] as String;
      if (existingNames.contains(name.toLowerCase())) continue;
      final srv = ServiceOffering(
        id: '',
        providerId: providerId,
        providerName: providerName,
        name: name,
        description: item['description'] as String,
        category: item['category'] as String,
        price: item['price'] as double,
        durationMinutes: item['durationMinutes'] as int,
        active: true,
        createdAt: now,
        updatedAt: now,
      );
      await addService(srv);
      addedCount++;
    }
    return addedCount;
  }

  /// Completes a consultation or clinic service booking, and automatically synchronizes
  /// the diagnosis into the Cat's medical history (VetVisit), records the newly measured weight (WeightLog),
  /// schedules/adds the administered vaccine (VaccineRecord), updates gender to Neutered/Spayed if surgery was performed,
  /// and automatically creates a confirmed Follow-Up Reservation if `followUpDate` is set.
  Future<void> completeAppointmentWithClinicalEMR({
    required String appointmentId,
    required bool isBooking,
    required String catId,
    required String ownerId,
    required String clinicName,
    required String diagnosisNotes,
    String? catName,
    String? ownerName,
    String? catBreed,
    double? recordedWeightKg,
    double? temperatureCelsius,
    String? vaccineTypeGiven,
    bool isKaponPerformed = false,
    String? prescribedMedicine,
    DateTime? followUpDate,
    double? totalBillPhp,
  }) async {
    try {
      final now = DateTime.now();
      final currentUser = _auth.currentUser;
      final providerId = currentUser?.uid ?? '';

      final visitReason = isKaponPerformed
          ? 'Spay / Neuter Surgery (Kapon)'
          : ((vaccineTypeGiven != null && vaccineTypeGiven.isNotEmpty && vaccineTypeGiven != 'None')
              ? 'Vaccination ($vaccineTypeGiven)'
              : 'Clinical Consultation');

      // Build rich clinical summary note for the appointment & receipt
      final summaryParts = <String>[diagnosisNotes.trim()];
      if (temperatureCelsius != null && temperatureCelsius > 0) {
        summaryParts.add('Temp: ${temperatureCelsius.toStringAsFixed(1)}°C');
      }
      if (recordedWeightKg != null && recordedWeightKg > 0) {
        summaryParts.add('Weight: ${recordedWeightKg.toStringAsFixed(2)} kg');
      }
      if (vaccineTypeGiven != null && vaccineTypeGiven.isNotEmpty && vaccineTypeGiven != 'None') {
        summaryParts.add('Vaccine: $vaccineTypeGiven');
      }
      if (isKaponPerformed) {
        summaryParts.add('Procedure: Kapon (Spay/Neuter)');
      }
      if (prescribedMedicine != null && prescribedMedicine.trim().isNotEmpty) {
        summaryParts.add('Rx: ${prescribedMedicine.trim()}');
      }
      if (followUpDate != null) {
        summaryParts.add('Auto-Follow-Up: ${ followUpDate.toLocal().toString().split(' ')[0] }');
      }
      if (totalBillPhp != null && totalBillPhp > 0) {
        summaryParts.add('Total Bill: ₱${totalBillPhp.toStringAsFixed(0)}');
      }
      final richSummaryNote = summaryParts.join(' • ');

      final emrPayload = <String, dynamic>{
        'catId': catId,
        'ownerId': ownerId,
        'clinicName': clinicName,
        'visitReason': visitReason,
        'diagnosisNotes': diagnosisNotes.trim(),
        'recordedWeightKg': recordedWeightKg,
        'temperatureCelsius': temperatureCelsius,
        'vaccineTypeGiven': (vaccineTypeGiven == 'None') ? null : vaccineTypeGiven,
        'isKaponPerformed': isKaponPerformed,
        'prescribedMedicine': prescribedMedicine?.trim(),
        'followUpDate': followUpDate != null ? Timestamp.fromDate(followUpDate) : null,
        'totalBillPhp': totalBillPhp,
        'completedAt': Timestamp.fromDate(now),
      };

      // 1. Mark Appointment Completed with the provider note + embedded clinicalEmrPayload
      if (isBooking) {
        await _firestore.collection('bookings').doc(appointmentId).update({
          'status': RequestStatus.completed.toValue(),
          'providerNote': richSummaryNote,
          'clinicalEmrPayload': emrPayload,
          'updatedAt': Timestamp.now(),
        });
      } else {
        await _firestore.collection('reservations').doc(appointmentId).update({
          'status': RequestStatus.completed.toValue(),
          'providerNote': richSummaryNote,
          'clinicalEmrPayload': emrPayload,
          'updatedAt': Timestamp.now(),
        });
      }

      // 2. Automatically log VetVisit to Cat's permanent medical history (deterministic ID avoids duplicates)
      try {
        final visitDoc = _firestore.collection('vet_visits').doc('emr_$appointmentId');
        final visit = VetVisit(
          id: visitDoc.id,
          catId: catId,
          visitDate: now,
          clinicName: clinicName,
          reason: visitReason,
          diagnosis: richSummaryNote,
          prescribedMedicine: prescribedMedicine,
          followUpDate: followUpDate,
        );
        final visitMap = visit.toMap()..['userId'] = ownerId;
        await visitDoc.set(visitMap);
      } catch (_) {}

      // 3. Automatically log newly measured Weight (WeightLog) & update Cat's current weight
      if (recordedWeightKg != null && recordedWeightKg > 0) {
        try {
          final weightDoc = _firestore.collection('weight_logs').doc('emr_w_$appointmentId');
          final wLog = WeightLog(
            id: weightDoc.id,
            catId: catId,
            weight: recordedWeightKg,
            date: now,
            notes: 'Clinically recorded at $clinicName',
          );
          final wMap = wLog.toMap()..['userId'] = ownerId;
          await weightDoc.set(wMap);
        } catch (_) {}

        try {
          await _firestore.collection('cats').doc(catId).update({
            'weight': recordedWeightKg,
            'updatedAt': Timestamp.now(),
          });
        } catch (_) {}
      }

      // 4. Automatically log administered vaccine (VaccineRecord) & compute next due date
      if (vaccineTypeGiven != null && vaccineTypeGiven.isNotEmpty && vaccineTypeGiven != 'None') {
        try {
          final nextDue = VaccineRecord.calculateNextDue(vaccineTypeGiven, now);
          final vaxDoc = _firestore.collection('vaccines').doc('emr_vax_$appointmentId');
          final vax = VaccineRecord(
            id: vaxDoc.id,
            catId: catId,
            type: vaccineTypeGiven,
            dateGiven: now,
            nextDueDate: nextDue,
            clinicName: clinicName,
            notes: 'Administered at $clinicName',
          );
          final vaxMap = vax.toMap()..['userId'] = ownerId;
          await vaxDoc.set(vaxMap);
        } catch (_) {}
      }

      // 5. Automatically update Cat's gender to Neutered/Spayed if Kapon was performed
      if (isKaponPerformed) {
        try {
          final catSnap = await _firestore.collection('cats').doc(catId).get();
          if (catSnap.exists && catSnap.data() != null) {
            final currentGender = (catSnap.data()!['gender'] ?? '').toString().toLowerCase();
            final newGender = currentGender.contains('female') ? 'Spayed' : 'Neutered';
            await _firestore.collection('cats').doc(catId).update({
              'gender': newGender,
              'updatedAt': Timestamp.now(),
            });
          }
        } catch (_) {}
      }

      // 6. If medicine was prescribed, save active prescription on the cat doc
      if (prescribedMedicine != null && prescribedMedicine.trim().isNotEmpty) {
        try {
          await _firestore.collection('cats').doc(catId).update({
            'activePrescription': {
              'medicine': prescribedMedicine.trim(),
              'prescribedAt': Timestamp.now(),
              'prescribedBy': clinicName,
            },
          });
        } catch (_) {}
      }

      // 7. AUTOMATED FOLLOW-UP APPOINTMENT SCHEDULING:
      // If a followUpDate is set, automatically create an Accepted Follow-Up Reservation at 10:00 AM!
      if (followUpDate != null && providerId.isNotEmpty) {
        try {
          final followUpSlot = DateTime(
            followUpDate.year,
            followUpDate.month,
            followUpDate.day,
            10,
            0,
          );
          final followUpDoc = _firestore.collection('reservations').doc('followup_$appointmentId');
          final followUpReason = isKaponPerformed
              ? 'Post-Op Kapon Suture & Healing Check'
              : ((vaccineTypeGiven != null && vaccineTypeGiven != 'None')
                  ? 'Booster / Post-Vaccination Follow-Up ($vaccineTypeGiven)'
                  : 'Clinical Follow-Up Consultation');
          final queueNum = 'Q-FUP-${(catName ?? 'C').isNotEmpty ? (catName ?? 'C')[0].toUpperCase() : 'C'}';
          final followUpRes = Reservation(
            id: followUpDoc.id,
            ownerId: ownerId,
            ownerName: ownerName ?? 'Pet Owner',
            catId: catId,
            catName: catName ?? 'Patient Cat',
            catBreed: catBreed ?? 'Feline',
            vetId: providerId,
            vetName: clinicName,
            visitType: 'Follow-up',
            requestedAt: followUpSlot,
            notes: '⚡ Auto-Scheduled Follow-Up from visit on ${now.toLocal().toString().split(' ')[0]}: $followUpReason',
            status: RequestStatus.accepted,
            providerNote: '⚡ Automatically scheduled by $clinicName during EMR discharge ($queueNum).',
            queueNumber: queueNum,
            createdAt: now,
            updatedAt: now,
          );
          await followUpDoc.set(followUpRes.toMap());
        } catch (_) {}
      }
    } on FirebaseException catch (e) {
      throw AppException('Error saving clinical records (${e.code}): ${e.message}');
    } catch (e) {
      throw AppException('Failed to complete visit: $e');
    }
  }

  /// Ensures that any completed appointment containing `clinicalEmrPayload` is 100% synced
  /// to the Pet Owner's `vet_visits`, `weight_logs`, `vaccines`, and `cats` documents
  /// even if strict Firestore security rules prevented cross-account writes during the Vet session.
  final Set<String> _syncedEmrAppointmentIds = {};

  Future<void> syncCompletedClinicalEMRForOwner({
    List<Reservation> reservations = const [],
    List<Booking> bookings = const [],
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    Future<void> processPayload(String apptId, Map<String, dynamic> payload) async {
      if (_syncedEmrAppointmentIds.contains(apptId)) return;
      _syncedEmrAppointmentIds.add(apptId);

      final catId = (payload['catId'] ?? '').toString();
      if (catId.isEmpty) return;
      final clinicName = (payload['clinicName'] ?? 'Veterinary Clinic').toString();
      final visitReason = (payload['visitReason'] ?? 'Clinical Consultation').toString();
      final diagnosisNotes = (payload['diagnosisNotes'] ?? '').toString();
      final prescribedMedicine = payload['prescribedMedicine']?.toString();
      final recordedWeightKg = (payload['recordedWeightKg'] is num)
          ? (payload['recordedWeightKg'] as num).toDouble()
          : null;
      final vaccineTypeGiven = payload['vaccineTypeGiven']?.toString();
      final isKaponPerformed = payload['isKaponPerformed'] == true;

      DateTime completedAt = DateTime.now();
      if (payload['completedAt'] is Timestamp) {
        completedAt = (payload['completedAt'] as Timestamp).toDate();
      }
      DateTime? followUpDate;
      if (payload['followUpDate'] is Timestamp) {
        followUpDate = (payload['followUpDate'] as Timestamp).toDate();
      }

      try {
        final visitRef = _firestore.collection('vet_visits').doc('emr_$apptId');
        final visitSnap = await visitRef.get();
        if (!visitSnap.exists) {
          final visit = VetVisit(
            id: visitRef.id,
            catId: catId,
            visitDate: completedAt,
            clinicName: clinicName,
            reason: visitReason,
            diagnosis: diagnosisNotes,
            prescribedMedicine: prescribedMedicine,
            followUpDate: followUpDate,
          );
          await visitRef.set(visit.toMap()..['userId'] = user.uid);
        }

        if (recordedWeightKg != null && recordedWeightKg > 0) {
          final wRef = _firestore.collection('weight_logs').doc('emr_w_$apptId');
          final wSnap = await wRef.get();
          if (!wSnap.exists) {
            final wLog = WeightLog(
              id: wRef.id,
              catId: catId,
              weight: recordedWeightKg,
              date: completedAt,
              notes: 'Clinically recorded at $clinicName',
            );
            await wRef.set(wLog.toMap()..['userId'] = user.uid);
            await _firestore.collection('cats').doc(catId).update({
              'weight': recordedWeightKg,
              'updatedAt': Timestamp.now(),
            });
          }
        }

        if (vaccineTypeGiven != null && vaccineTypeGiven.isNotEmpty && vaccineTypeGiven != 'None') {
          final vaxRef = _firestore.collection('vaccines').doc('emr_vax_$apptId');
          final vaxSnap = await vaxRef.get();
          if (!vaxSnap.exists) {
            final nextDue = VaccineRecord.calculateNextDue(vaccineTypeGiven, completedAt);
            final vax = VaccineRecord(
              id: vaxRef.id,
              catId: catId,
              type: vaccineTypeGiven,
              dateGiven: completedAt,
              nextDueDate: nextDue,
              clinicName: clinicName,
              notes: 'Administered at $clinicName',
            );
            await vaxRef.set(vax.toMap()..['userId'] = user.uid);
          }
        }

        if (isKaponPerformed) {
          final catSnap = await _firestore.collection('cats').doc(catId).get();
          if (catSnap.exists && catSnap.data() != null) {
            final currentGender = (catSnap.data()!['gender'] ?? '').toString().toLowerCase();
            if (!currentGender.contains('spayed') && !currentGender.contains('neutered')) {
              final newGender = currentGender.contains('female') ? 'Spayed' : 'Neutered';
              await _firestore.collection('cats').doc(catId).update({
                'gender': newGender,
                'updatedAt': Timestamp.now(),
              });
            }
          }
        }
      } catch (_) {}
    }

    for (final r in reservations) {
      if (r.status == RequestStatus.completed && r.clinicalEmrPayload != null) {
        await processPayload(r.id, r.clinicalEmrPayload!);
      }
    }
    for (final b in bookings) {
      if (b.status == RequestStatus.completed && b.clinicalEmrPayload != null) {
        await processPayload(b.id, b.clinicalEmrPayload!);
      }
    }
  }

  /// Automatically matches and checks-in a patient using their scanned QR Code.
  /// Transitions appointment status to Accepted/Checked-In, assigns an automatic Queue Number,
  /// and returns the Cat profile and appointment details.
  Future<Map<String, dynamic>> checkInPatientWithQR({
    required String catId,
    required String providerId,
    required String providerName,
  }) async {
    try {
      Cat? cat;
      try {
        final catDoc = await _firestore.collection('cats').doc(catId).get();
        if (catDoc.exists && catDoc.data() != null) {
          cat = Cat.fromMap(catDoc.id, catDoc.data()!);
        }
      } catch (_) {}

      // Look for any pending or accepted reservation for this cat with this provider
      final resDocs = await _firestore
          .collection('reservations')
          .where('vetId', isEqualTo: providerId)
          .where('catId', isEqualTo: catId)
          .get();

      Reservation? matchedReservation;
      for (final doc in resDocs.docs) {
        final r = Reservation.fromMap(doc.id, doc.data());
        if (r.status == RequestStatus.pending || r.status == RequestStatus.accepted) {
          matchedReservation = r;
          break;
        }
      }

      Booking? matchedBooking;
      if (matchedReservation == null) {
        final bookDocs = await _firestore
            .collection('bookings')
            .where('clinicId', isEqualTo: providerId)
            .where('catId', isEqualTo: catId)
            .get();

        for (final doc in bookDocs.docs) {
          final b = Booking.fromMap(doc.id, doc.data());
          if (b.status == RequestStatus.pending || b.status == RequestStatus.accepted) {
            matchedBooking = b;
            break;
          }
        }
      }

      if (cat == null && matchedReservation != null) {
        cat = Cat(
          id: matchedReservation.catId,
          userId: matchedReservation.ownerId,
          name: matchedReservation.catName,
          breed: matchedReservation.catBreed,
          birthDate: DateTime.now().subtract(const Duration(days: 365)),
          weight: 4.0,
          gender: 'Unspecified',
        );
      } else if (cat == null && matchedBooking != null) {
        cat = Cat(
          id: matchedBooking.catId,
          userId: matchedBooking.ownerId,
          name: matchedBooking.catName,
          breed: matchedBooking.catBreed,
          birthDate: DateTime.now().subtract(const Duration(days: 365)),
          weight: 4.0,
          gender: 'Unspecified',
        );
      }

      if (cat == null) {
        throw AppException('Cat profile or active appointment not found for ID "$catId".');
      }

      final queueNum = 'Q-${(DateTime.now().minute % 50 + 1).toString().padLeft(2, '0')}-${cat.name.isNotEmpty ? cat.name[0].toUpperCase() : 'X'}';

      if (matchedReservation != null) {
        await _firestore.collection('reservations').doc(matchedReservation.id).update({
          'status': RequestStatus.accepted.toValue(),
          'checkedInAt': Timestamp.now(),
          'queueNumber': queueNum,
          'providerNote': '🟢 Checked-In at Clinic Reception via QR ($queueNum).',
          'updatedAt': Timestamp.now(),
        });
      } else if (matchedBooking != null) {
        await _firestore.collection('bookings').doc(matchedBooking.id).update({
          'status': RequestStatus.accepted.toValue(),
          'checkedInAt': Timestamp.now(),
          'queueNumber': queueNum,
          'providerNote': '🟢 Checked-In at Clinic Reception via QR ($queueNum).',
          'updatedAt': Timestamp.now(),
        });
      } else {
        // Walk-in QR scan: attempt to auto-create a live Walk-In Reservation in the queue
        try {
          final now = DateTime.now();
          final walkInDoc = _firestore.collection('reservations').doc();
          final walkInRes = Reservation(
            id: walkInDoc.id,
            ownerId: cat.userId,
            ownerName: 'Walk-In Pet Owner',
            catId: cat.id,
            catName: cat.name,
            catBreed: cat.breed,
            vetId: providerId,
            vetName: providerName,
            visitType: 'Checkup',
            requestedAt: now,
            notes: '⚡ Auto-Created via Walk-In Reception QR Scan',
            status: RequestStatus.accepted,
            providerNote: '🟢 Walk-In Checked-In via QR ($queueNum).',
            queueNumber: queueNum,
            checkedInAt: now,
            createdAt: now,
            updatedAt: now,
          );
          await walkInDoc.set(walkInRes.toMap());
          matchedReservation = walkInRes;
        } catch (_) {}
      }

      return {
        'cat': cat,
        'queueNumber': queueNum,
        'hasAppointment': matchedReservation != null || matchedBooking != null,
        'reservation': matchedReservation,
        'booking': matchedBooking,
      };
    } on FirebaseException catch (e) {
      throw AppException('QR Check-In failed (${e.code}): ${e.message}');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException('Check-in error: $e');
    }
  }
}
