# Completed Features vs. Remaining Features

## ✅ Completed

### Authentication
- Email/password registration and sign-in (Firebase Authentication)
- Client-side form validation (email format, password length) with inline error text
- Human-readable error messages mapped from Firebase Auth error codes (wrong password,
  user not found, email already in use, network error, etc.)

### Cat Profile — Full CRUD
- **Create** — Add Cat screen, with name/breed/weight/diet/initial vaccine schedule
- **Read** — live, real-time list on the Home screen; live detail view on Cat Detail screen
- **Update** — Edit Profile dialog (name, breed, weight)
- **Delete** — delete icon + confirmation dialog on Cat Detail screen

### Health Records (Create + Read only — see Remaining below)
- Weight logs — add + real-time list + trend chart
- Vaccine records — add + real-time list + status (upcoming/overdue) + auto-computed next
  due date + local reminder notification
- Vet visit records — add + real-time list with expandable detail

### Search / Filter
- Live search bar on the My Cats list, filtering by name or breed as the user types

### Error Handling
- Centralized `AppException` type thrown by every `FirebaseService` method
- try/catch + user-facing `SnackBar` on every write path in the UI (create, update, delete,
  sign in, sign up)
- Retry affordance shown if the cat list stream itself errors out

### API Integration
- Real HTTP GET/POST/PATCH/DELETE requests to the Firestore REST API (`ApiService`)
- Bearer-token authentication using the signed-in user's Firebase ID token
- In-app API Test Console to trigger and inspect real requests/responses

### Supporting Features
- QR health card generation
- Offline persistence (Firestore local cache)
- Health dashboard (total cats, upcoming/overdue vaccine counts, recent activity)

## 🔧 Remaining / Recommended for the Final Project

1. **Update/Delete for sub-records.** Weight logs, vaccine records, and vet visit records
   currently support Create and Read only. Editing a mislogged weight or deleting a
   duplicate vaccine record isn't possible yet — a user has to leave it or work around it.
2. **Consolidate `add_cat_screen.dart` onto `FirebaseService`.** It currently calls
   `FirebaseFirestore.instance` directly instead of `FirebaseService.addCat()`, which is an
   inconsistency worth cleaning up so all Firestore access goes through one layer.
3. **Tighten Firestore security rules.** Current rules (see `docs/05_Database_Design.md`)
   allow any authenticated user to read/write any cat document — they should be scoped so a
   user can only access documents where `userId` matches their own UID.
4. **Password reset flow.** Not implemented.
5. **Photo upload for cat profiles.** The data model reserves an `imageUrl` field, but there
   is no picker/upload UI or Firebase Storage integration yet.
6. **Push notifications.** Vaccine reminders currently use local, on-device notifications
   only; Firebase Cloud Messaging would make reminders reliable even if the app hasn't been
   opened recently.
7. **Automated tests.** No unit or widget tests currently exist.
8. **A real device build/run pass.** This round of changes was written and reviewed in an
   environment without the Flutter SDK; a full `flutter pub get && flutter run` should be
   done before the final submission to catch anything a manual review could miss.
