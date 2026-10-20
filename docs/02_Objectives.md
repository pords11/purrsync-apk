# Project Objectives

## General Objective
To design and develop **PurrSync**, a mobile cat health-management application that allows
owners to create, view, update, and delete cat health records through a cloud-synced,
offline-capable system.

## Specific Objectives

1. **Authentication & Account Management**
   - Allow a user to register and sign in with an email and password.
   - Validate credentials client-side before submitting them, and surface clear,
     human-readable error messages when authentication fails.

2. **Cat Profile Management (Create, Read, Update, Delete)**
   - Allow a user to create a profile for each cat they own (name, breed, weight, initial
     diet plan, and initial vaccine schedule).
   - Display all of a user's cats in a live, auto-updating list.
   - Allow a user to edit a cat's core profile fields (name, breed, weight) after creation.
   - Allow a user to permanently delete a cat's profile, guarded by a confirmation step.

3. **Health Record Tracking**
   - Let a user log a cat's weight over time and visualize the trend on a chart.
   - Let a user record vaccination events and automatically compute the next due date based
     on vaccine type.
   - Let a user record veterinary visits, including reason, diagnosis, and optional
     follow-up date.

4. **Findability**
   - Let a user search/filter their cat list by name or breed once the list grows beyond a
     handful of cats.

5. **Reliability**
   - Ensure the app remains usable when the device has no internet connection, by enabling
     Firestore's offline persistence.
   - Ensure that failures (network errors, invalid input, permission errors) are caught and
     shown to the user instead of crashing the app or failing silently.

6. **Interoperability / API Access**
   - In addition to using the Firebase SDK for the main application, demonstrate direct
     HTTP-level integration with the Firestore REST API (GET, POST, PATCH, DELETE),
     authenticated with the user's Firebase ID token.

7. **Shareability**
   - Allow a cat's core health information to be exported as a scannable QR code, so it can
     be shared quickly (e.g., with a veterinary clinic).

## Learning Objectives (Course-Aligned)
- Apply complete CRUD functionality against a real cloud database (Cloud Firestore).
- Apply client-side form validation and centralized error handling in a mobile application.
- Integrate a mobile client with a backend through both an SDK and a raw REST API.
- Produce supporting technical documentation (architecture diagram, ERD, progress report)
  consistent with the delivered code.
