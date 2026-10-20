# PurrSync — Project Overview

## Project Title
**PurrSync: A Mobile-Based Health, Vaccination, and Nutrition Tracking System for Multi-Cat Households**

## Description
PurrSync is a cross-platform mobile application, built with Flutter and Cloud Firestore,
that helps cat owners manage the health records of one or more cats from a single account.
Instead of relying on paper vaccination booklets, scattered notes, or memory, an owner can
register their cats in the app and maintain a running digital record of each cat's weight
history, vaccination schedule, and veterinary visits — all synced in real time to the cloud
and accessible offline.

The system is aimed at owners who care for **multiple cats** (e.g. multi-cat households,
foster carers, small shelters), where keeping track of who is due for which vaccine, and
whose weight has been trending up or down, becomes difficult to do manually.

## Who It's For
- Individual cat owners tracking one or more pets
- Foster/rescue caretakers managing several cats at once
- Anyone who wants a shareable digital health record for their cat (via the in-app QR
  health card) — for example, to hand to a veterinarian at a visit

## Core Value Proposition
1. **Never miss a vaccine again** — the app calculates next-due dates automatically and
   schedules a local device reminder.
2. **See health trends, not just data points** — a weight chart shows whether a cat is
   gaining, losing, or holding steady.
3. **Works without signal** — Firestore's offline persistence means the app is usable in a
   vet clinic with poor connectivity, syncing automatically once back online.
4. **One account, many cats** — every record type (weight, vaccine, vet visit) is scoped to
   a specific cat, which is scoped to the signed-in owner.

## Platform & Stack
| Layer | Technology |
|---|---|
| Client | Flutter (Dart), Material 3 |
| Authentication | Firebase Authentication (email/password) |
| Database | Cloud Firestore, offline persistence enabled |
| Direct REST access | Firestore REST API via `http` package (see `docs/07_API_Integration.md`) |
| Local notifications | `flutter_local_notifications` |
| Charts | `fl_chart` |
| QR sharing | `qr_flutter` |

See `docs/04_Architecture_and_Flowchart.md` for the full system diagram and
`docs/05_Database_Design.md` for the Firestore schema.
