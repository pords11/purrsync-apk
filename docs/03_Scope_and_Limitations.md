# Scope and Limitations

## In Scope

### Functional Scope
- Email/password registration and login (Firebase Authentication)
- Create, read, update, and delete cat profiles
- Create and read weight logs, vaccine records, and vet visit records per cat
- Client-side search/filter of a user's own cat list by name or breed
- Automatic next-due-date calculation for vaccines, with a local device notification
  scheduled ahead of the due date
- Weight trend chart per cat
- QR code generation summarizing a cat's health information
- Offline data access via Firestore's built-in offline persistence
- A diagnostic "API Test Console" that issues real GET/POST/PATCH/DELETE HTTP requests to
  the Firestore REST API, separate from the main app's SDK-based data flow

### Technical Scope
- Single Flutter codebase targeting Android as the primary tested platform (the project is
  also configured for iOS/web/desktop by the Flutter tooling, but only Android has been
  exercised during this project)
- Firebase project `purrsync-42b2c` used as the sole backend
- No custom backend server — Firebase (Auth + Firestore) is the entire backend

## Out of Scope / Not Implemented

- **Multi-user sharing of a single cat profile** (e.g., co-ownership between two accounts).
  Each cat belongs to exactly one `userId`.
- **Push notifications** (Firebase Cloud Messaging). Vaccine reminders use local,
  on-device notifications only, which only fire while the app has been opened at least once
  on that device and the OS has not cleared scheduled alarms.
- **Photo upload/storage** for cat profile pictures. The data model has an `imageUrl` field
  reserved for this, but no upload UI or Firebase Storage integration was built.
- **Password reset / "forgot password" flow.**
- **Editing or deleting individual weight logs, vaccine records, or vet visit records**
  after they are created (Update/Delete is implemented for the parent Cat Profile only, not
  for these sub-records — see the Progress Report for details).
- **Role-based access / admin features** (e.g., a vet-facing dashboard). The app is
  single-role: pet owner.
- **Automated test suite.** Manual testing only; see `docs/10_Test_Plan.md`.
- **Full compiler verification in this delivery.** The code was written and manually
  reviewed (syntax structure, brace/paren balance, cross-file references) but could not be
  run through `flutter analyze` / `flutter build` in the environment this project was
  finished in, because that environment has no Flutter SDK and no access to pub.dev. It
  should be built and run once on your own machine before your live demo — see the note in
  `docs/06_Progress_Report.md`.

## Assumptions
- The user has (or will create) a Firebase project and has placed valid
  `firebase_options.dart` / `google-services.json` credentials in the project, matching
  project ID `purrsync-42b2c`.
- Firestore security rules permit an authenticated user to read/write documents in `cats`,
  `weight_logs`, `vaccines`, and `vet_visits` where the document's `userId`/`catId` matches
  their own data, and to read/write `api_test_logs` when authenticated (see
  `docs/07_API_Integration.md` for the exact rule needed).
- The grading demonstration will be run on a physical Android device or emulator with
  Google Play Services available (required by `firebase_auth`/`cloud_firestore`).
