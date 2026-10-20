# API Integration and Testing

## Two Different Ways This App Talks to the Backend

It's worth being explicit about this, because the checklist's "API Integration" section
(GET/POST/PUT/PATCH/DELETE, API connection, error handling) is usually written with a
hand-rolled REST backend in mind. PurrSync's **main app** does not do that — it uses the
**Firebase SDK** (`cloud_firestore`, `firebase_auth`), which manages its own networking,
retries, caching, and offline queueing internally. There is no `http.get(...)` call
anywhere in the main CRUD flow.

To make sure this checklist section is genuinely, verifiably true rather than just asserted,
a **second, independent path** to the same backend was added: `ApiService`
(`lib/services/api_service.dart`), which speaks raw HTTPS directly to the
**[Firestore REST API](https://firebase.google.com/docs/firestore/use-rest-api)** — no SDK
involved. This is exercised through a real screen, the **API Test Console**
(`lib/screens/api_test_screen.dart`, reachable from the icon in the Home screen's app bar),
so every button press is a genuine network call you can watch happen and screenshot.

## Connection Details
- **Base URL:** `https://firestore.googleapis.com/v1/projects/purrsync-42b2c/databases/(default)/documents`
- **Authentication:** Bearer token — the signed-in user's Firebase ID token
  (`FirebaseAuth.instance.currentUser.getIdToken()`), sent as `Authorization: Bearer <token>`
  on every request. This satisfies the "Authentication/Authorization Implemented" checklist
  item for the API layer specifically (separate from the app-level login, which uses
  Firebase Auth directly).
- **Target collection:** `api_test_logs`, kept separate from real cat data so testing never
  risks corrupting a cat's records.

## Requests Implemented

| Verb | Method | Endpoint | Purpose |
|---|---|---|---|
| GET | `ApiService.getDoc(docId)` | `/api_test_logs/{docId}` | Read back a single test document |
| POST | `ApiService.postDoc(note: ...)` | `/api_test_logs` | Create a new test document, auto-ID |
| PATCH | `ApiService.patchDoc(docId, newNote: ...)` | `/api_test_logs/{docId}?updateMask.fieldPaths=note` | Update one field on a document |
| DELETE | `ApiService.deleteDoc(docId)` | `/api_test_logs/{docId}` | Remove a document |

Firestore's REST API represents field values in a typed wrapper format (e.g.
`{"stringValue": "..."}`), which is why the request bodies in `api_service.dart` look a
little different from a typical plain-JSON REST API — this is standard for Firestore's REST
API, not a bug.

## Responses
Each call returns an `ApiResult` (status code, method, URL, pretty-printed JSON body,
success flag), which the API Test Console renders directly on screen — status code as a
colored chip, full JSON body in a scrollable monospace panel. This is what should appear in
your "API Testing Screenshots/Logs" evidence.

## Error Handling
- If the user is not signed in, `ApiService` throws before making any network call
  (`"You must be signed in to call the API."`), rather than sending an unauthenticated
  request that would fail anyway.
- Non-2xx responses are still returned as a normal `ApiResult` (with `success: false`) rather
  than thrown, so the Test Console can display *why* a call failed (e.g. a 403 from a
  security-rule rejection, a 404 for a GET against a deleted document) instead of just
  crashing.
- The console itself wraps every call in try/catch and shows network-level failures
  (e.g., no internet) in a red banner.

## ⚠️ One Setup Step You Need To Do
The `api_test_logs` collection needs its own Firestore security rule, or every call from the
API Test Console will fail with a `403 PERMISSION_DENIED`:
```
match /api_test_logs/{id} {
  allow read, write: if request.auth != null;
}
```
Add this to your project's Firestore rules (see `docs/05_Database_Design.md` for the full
rules block) before testing this feature.

## Suggested Test Sequence (for your screenshots)
1. Open the API Test Console from the Home screen's app bar (cloud icon).
2. Tap **POST** — creates a document, confirm you see a `200` and a JSON body with a
   `name` field ending in `api_test_logs/<some-id>`.
3. Tap **GET** — confirm the same document comes back, including the `note` value you just
   posted.
4. Tap **PATCH** — confirm the response's `note` field has changed.
5. Tap **DELETE** — confirm you get back an empty `{}` body with a `200`.
6. Optionally, open the Firestore console in a browser and show the `api_test_logs`
   collection updating live as you tap through steps 2–5, for your "Database Screenshot"
   evidence.

## Public Third-Party REST API: Cat Facts API

In addition to the Google Cloud Firestore REST API, PurrSync integrates with a live public third-party REST API:

- **Endpoint:** `https://catfact.ninja/fact`
- **Method:** `GET`
- **Purpose:** Fetches daily curated feline health, nutrition, and care facts displayed dynamically at the top of the "Discover & Community" tab.
- **Implementation:** `ApiService.fetchDailyCatFact()` using Flutter's `http` package with a 5-second timeout and graceful fallback to offline educational cat care facts if network connectivity is absent.
- **Screen Location:** Discover Screen → "Vet Clinics" tab → Top banner with lightbulb icon: "Daily Cat Care Fact (Live REST API)".

## Third-Party OAuth API: Google Sign-In & Firebase Auth

PurrSync integrates official third-party OAuth identity verification via Google Identity Services:

- **Provider:** Google Identity Services (`google_sign_in: ^7.2.0`)
- **OAuth Scope:** OpenID Connect, Profile, Email
- **Protocol:** OAuth 2.0 / OpenID Connect (OIDC) token exchange with Firebase Authentication (`GoogleAuthProvider.credential`)
- **Workflow:**
  1. User taps "Sign in with Google" button on the Login/Registration screen.
  2. The Google Identity modal allows single-tap authentication using system Google credentials.
  3. `GoogleSignIn.instance.authenticate()` retrieves the cryptographically-signed Google `idToken`.
  4. PurrSync exchanges the credential with Firebase Auth (`_auth.signInWithCredential(credential)`).
  5. The backend verifies whether a user record exists in Firestore `users/{uid}`; if new, it saves the profile with their selected role (Pet Owner or Vet / Clinic provider) seamlessly.
- **Error & Edge-Case Handling:** Cancelled sign-in attempts, network drops, and account linkage conflicts surface clear, user-friendly error banners.
