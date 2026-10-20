# System Architecture

See the full diagram: **`assets/architecture_diagram.svg`**

## Layers

### 1. Presentation Layer (`lib/screens/`)
Flutter widgets responsible for UI and user interaction only — no direct Firestore calls
happen here except through the service layer below.

| Screen | File | Responsibility |
|---|---|---|
| Login / Register | `screens/auth/login_screen.dart` | Auth entry point, validated form |
| Home (My Cats + Dashboard) | `screens/home_screen.dart` | Live cat list with search, health dashboard |
| Add Cat | `screens/add_cat_screen.dart` | Create flow for a new cat profile |
| Cat Detail | `screens/cat_detail_screen.dart` | Update/Delete profile; Vaccines/Weight/Vet Visits tabs |
| QR Health Card | `screens/qr_health_card.dart` | Generates a shareable QR summary |
| API Test Console | `screens/api_test_screen.dart` | Fires real REST calls for API integration testing |

### 2. Service Layer (`lib/services/`)
Encapsulates all backend communication, so screens never talk to Firebase directly.

- **`firebase_service.dart`** — wraps the Firebase Auth and Cloud Firestore **SDKs**. Every
  method either returns data/streams or throws an `AppException` with a message that is
  already safe to display to the user.
- **`api_service.dart`** — a second, independent path to the same backend that speaks
  **raw HTTPS** to the Firestore REST API directly (GET/POST/PATCH/DELETE), authorized with
  the signed-in user's Firebase ID token. Used only by the API Test Console, against a
  dedicated `api_test_logs` collection.
- **`notification_service.dart`** — schedules local device notifications for upcoming
  vaccine due dates.

### 3. Backend (Firebase / Google Cloud)
- **Firebase Authentication** — email/password accounts, issues the ID tokens used by both
  the SDK and the REST layer.
- **Cloud Firestore** — the single source of truth for all application data, accessed two
  ways (SDK for the main app, REST for the diagnostics console) but storing data in the
  same collections either way.

### 4. On-device
- **`flutter_local_notifications`** — schedules the vaccine reminder alarm on the device
  itself; this part of the system does not depend on connectivity once scheduled.

## Data Flow (Create example)
1. User fills in the Add Cat form (`add_cat_screen.dart`) → local form validation runs.
2. On submit, the screen calls Firestore directly through `FirebaseFirestore.instance` (this
   one screen predates `FirebaseService` and talks to Firestore inline; see
   `docs/08_Code_Samples.md` for why this is called out).
3. Firestore SDK queues the write locally (if offline) and syncs when connectivity returns.
4. Every other screen subscribed to that cat's data (`getCats()` stream) receives the update
   automatically and re-renders — no manual refresh needed.
5. If a next vaccine date was set, `NotificationService.scheduleVaccineReminder()` schedules
   a local alarm 3 days before that date.

## Navigation Flow
```
/login  (initial route)
  │
  ├─ (register) ─► Create Account dialog ─► /home
  └─ (sign in)  ─────────────────────────► /home
                                              │
                        ┌─────────────────────┼─────────────────────┐
                        │                                          │
                  My Cats tab                                Dashboard tab
                        │                                          │
              ┌─────────┼─────────┐                       (summary cards,
              │                   │                        recent activity)
        Add Cat Screen     Cat Detail Screen
        (Create)            │  │  │
                             │  │  └─ Vet Visits tab (Create, Read)
                             │  └──── Weight tab (Create, Read, chart)
                             └─────── Vaccines tab (Create, Read)
                             + Edit Profile dialog (Update)
                             + Delete icon (Delete)
                             + QR Health Card
        API Test Console (from Home app bar) — GET / POST / PATCH / DELETE via REST
```
