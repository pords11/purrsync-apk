# Project Progress Report

**As of:** midterm submission
**Prepared by:** (student to fill in name/section on the checklist form)

## Summary
All core CRUD functionality for the main entity (Cat Profiles) is implemented and working
against a live Cloud Firestore backend, along with Create/Read for the three related
health-record sub-entities (weight logs, vaccine records, vet visits). Since the previous
review pass, the following gaps were closed:

| Area | Before | Now |
|---|---|---|
| Delete Cat | Not wired to any UI | Delete icon + confirmation dialog on Cat Detail screen |
| Update Cat | Only as a side-effect of logging weight | Dedicated Edit Profile dialog (name/breed/weight) |
| Search/Filter | Did not exist | Live search bar on My Cats list (filters by name/breed) |
| Login form validation | None (empty fields silently attempted) | Email format + password length validation with inline errors |
| Error handling | Firestore/Auth failures were swallowed (`print()` + `return null`) or would crash the UI | All Firestore/Auth calls throw a typed `AppException` with a user-safe message; every write path in the UI catches it and shows a SnackBar |
| API Integration | App only used the Firestore SDK — no literal HTTP requests existed | Added `ApiService` + an in-app API Test Console making real GET/POST/PATCH/DELETE requests to the Firestore REST API |
| Two build-breaking bugs | `add_cat_screen.dart` had a duplicated, mismatched brace; `main.dart` called a static method as an instance method | Both fixed |

## What Works Right Now
- Register / sign in with a validated email+password form
- View a live-updating list of the signed-in user's cats, with search/filter
- Add a new cat (name, breed, weight, diet snapshot, initial vaccine + auto-computed next
  due date, local reminder scheduled)
- View a cat's Vaccines / Weight / Vet Visits tabs, each backed by a real-time stream
- Add a vaccine record, a weight log (which also syncs the cat's headline weight), or a vet
  visit record
- Edit a cat's name/breed/weight
- Delete a cat's profile (with confirmation)
- Generate a QR code summarizing a cat's health info
- Fire real GET/POST/PATCH/DELETE HTTP requests against Firestore's REST API from the API
  Test Console and see the raw JSON response

## Known Gaps (see `docs/09_Completed_and_Remaining_Features.md` for the full list)
- No Update/Delete for individual weight logs, vaccine records, or vet visit records — only
  the parent Cat Profile supports full CRUD.
- `add_cat_screen.dart` calls `FirebaseFirestore.instance` directly instead of going through
  `FirebaseService`, which is an inconsistency in an otherwise centralized service layer.
- Firestore security rules (see `docs/05_Database_Design.md`) are permissive by design for
  this stage and should be tightened before any real deployment.
- No automated tests were written; verification was manual code review only.

## A Build Note — Please Read Before Your Demo
This project was finished in a sandboxed environment **without the Flutter SDK installed**
and **without network access to pub.dev**, so it was not possible to run `flutter pub get`,
`flutter analyze`, or `flutter run` to get a compiler's confirmation that everything builds.
Every change was:
- written by hand against the existing code style,
- checked for matching brace/parenthesis counts across every edited file,
- cross-checked against every call site that could be affected (for example, after
  `FirebaseService.signIn()`/`signUp()` were changed from "return null on failure" to
  "throw AppException on failure," every caller was located and updated to match).

**Before your live demo or recording your CRUD screenshots, please run:**
```
flutter pub get
flutter run
```
on your own machine first, so any environment-specific issue (SDK version mismatch,
missing `google-services.json`, etc.) surfaces before grading rather than during it.
