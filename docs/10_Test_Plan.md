# Manual Test Plan

This is a test plan to execute yourself and capture as evidence — it is intentionally **not**
pre-filled with results, because results captured without actually running the app would be
fabricated evidence. Run through this list on your own device/emulator; each row tells you
exactly what to screenshot.

## Setup Checklist (do this first)
- [ ] `flutter pub get` completes without errors
- [ ] Firestore security rules from `docs/05_Database_Design.md` are applied to your project
      (including the `api_test_logs` rule)
- [ ] App launches to the Login screen on a device/emulator with internet access

## Auth
| # | Test | Steps | Expected Result |
|---|---|---|---|
| A1 | Empty submit | Tap "Login" with both fields empty | Inline "Email is required" / "Password is required" errors, no network call |
| A2 | Invalid email format | Enter `notanemail`, any password → Login | Inline "Enter a valid email address" error |
| A3 | Register | Toggle to Register, fill name/email/password, submit | Redirected to Home; new user visible in Firebase Console → Authentication |
| A4 | Wrong password | Sign in with a valid email, wrong password | Red error text: "Incorrect email or password." |
| A5 | Sign out | Tap logout icon on Home | Redirected to Login screen |

## Create
| # | Test | Steps | Expected Result |
|---|---|---|---|
| C1 | Add cat — valid | Tap +, fill name + weight, save | SnackBar "Cat Profile Saved! 🐾"; new cat appears in My Cats list immediately |
| C2 | Add cat — invalid weight | Enter weight `999`, save | Inline error "Must be between 0.1kg and 30kg"; form does not submit |
| C3 | Add vaccine record | Open a cat → Vaccines tab → +, fill fields, save | Record appears in the list with correct status chip |
| C4 | Add weight log | Weight tab → +, enter weight, save | New point appears on the chart; cat's headline weight updates |

## Read
| # | Test | Steps | Expected Result |
|---|---|---|---|
| R1 | Live list | Add a cat on one device/session, watch My Cats list on another | List updates without manual refresh |
| R2 | Search | Type part of a cat's name into the search bar | List narrows to matching cats in real time |
| R3 | Search — no match | Type a nonsense string | "No cats match ..." empty state shown |
| R4 | Offline read | Enable airplane mode, reopen app | Previously loaded cats still display (from Firestore's local cache) |

## Update
| # | Test | Steps | Expected Result |
|---|---|---|---|
| U1 | Edit profile | Open a cat → edit icon → change name/breed/weight → Save | SnackBar "Profile updated ✅"; new values shown immediately |
| U2 | Edit — invalid weight | Enter weight `0` → Save | Inline validation error; dialog stays open |

## Delete
| # | Test | Steps | Expected Result |
|---|---|---|---|
| D1 | Delete with confirm | Open a cat → delete icon → confirm | Returns to My Cats list; cat no longer present |
| D2 | Delete — cancel | Delete icon → Cancel | Dialog closes; cat still present |

## API Integration (REST APIs)
| # | Test | Steps | Expected Result |
|---|---|---|---|
| API1 | POST | Home → API icon → POST | Chip shows `POST 200`; JSON body includes a `name` ending in an `api_test_logs/<id>` |
| API2 | GET | Tap GET (after API1) | Chip shows `GET 200`; JSON `note` field matches what POST sent |
| API3 | PATCH | Tap PATCH | Chip shows `PATCH 200`; JSON `note` field has changed |
| API4 | DELETE | Tap DELETE | Chip shows `DELETE 200`; body is `{}` |
| API5 | Unauthenticated | Sign out, then try to reach the console or call `ApiService` directly | Throws "You must be signed in to call the API." before any network request |
| API6 | Cat Facts REST API | Open Discover Screen → Vet Clinics tab | Top card shows live "Daily Cat Care Fact (Live REST API)" fetched from `catfact.ninja` |

## Unified Roles & Provider Portal (Vet / Clinic)
| # | Test | Steps | Expected Result |
|---|---|---|---|
| P1 | Register as Vet/Clinic | Register screen → Select "Vet / Clinic" card → Fill clinic name, city, clock dial hours → Register | Account created, automatic verification email triggered, routes to Provider Dashboard |
| P2 | Email Verification Banner | Look at top of Dashboard or Owner Home | Amber banner "Email Not Verified" with "Resend" button; disappears once verified |
| P3 | Provider Services CRUD | Services tab → "Add Service" → Fill name, price, duration, category → Save | Service appears immediately in active services catalog; visible to Pet Owners |
| P4 | Provider Appointments Inbox | Appointments tab → Switch between "Consultations" & "Services" pills | Vet/Clinic can Accept, Decline (with custom note dialog), or Complete requests |
| P5 | Community News CRUD | Community tab → "New Post / Event" → Select date/expiry → Publish | Post appears in provider feed and Pet Owner Discover screen with "NEW" badge |

## Google Sign-In OAuth & Security
| # | Test | Steps | Expected Result |
|---|---|---|---|
| G1 | Google Sign-In Button | Login / Register screen → tap "Sign in with Google" | Native Google account chooser / popup opens |
| G2 | First-time Google Auth | Select Google account → role assigned based on selection | Account created in Firestore with chosen role, routed to respective dashboard |
| G3 | Google Sign-Out | Tap profile / logout button | Signs out from both Firebase and Google session |

## Date Validations & Smart Slot Management
| # | Test | Steps | Expected Result |
|---|---|---|---|
| V1 | Vaccine Date Prior to Birthdate | Add Vaccine dialog → Pick Date Given before cat's birthdate | Inline red banner: "Vaccine date cannot be before the cat's birthdate." and Save disabled/blocked |
| V2 | Visit Date Prior to Birthdate | Add Vet Visit dialog → Pick Visit Date before cat's birthdate | Inline red banner: "Visit date cannot be before the cat's birthdate." and Save disabled/blocked |
| S1 | Occupied Slots Warning | Reservation/Booking form → Pick date that has accepted appointments | Amber container shows "Already Booked / Occupied on this Date" with time range chips |
| S2 | Occupied Slot Prevention | Pick an occupied start time → Submit | Error message: "This time slot is already booked and accepted. Please choose a different time." |
| D3 | Mandatory Decline Reason | Provider Appointments → Tap Decline on any request → Leave reason empty → Tap Decline | Red inline error: "A reason is required so the pet owner is informed." Submission prevented until filled |

## Community Post Categories & Badges
| # | Test | Steps | Expected Result |
|---|---|---|---|
| N1 | Expanded Post Types | Provider Community → New Announcement → Open Post Type dropdown | Shows 6 types (Vaccine Drive, Schedule/Hours, Service Update, Payment/Facility, General, Others) |
| N2 | Custom Tag / Detail | Select "Schedule / Hours Update" or "Others" | Extra text field appears for custom notes / holiday hours |
| N3 | Color-Coded Badges | Discover Screen → Community / News | Each post renders an icon and color-coded category badge (e.g., Green for Drive, Amber for Schedule) |

## Error Handling
| # | Test | Steps | Expected Result |
|---|---|---|---|
| E1 | Firestore write failure | Temporarily set a Firestore rule to deny writes, try to add a cat | Red SnackBar with a specific error message, not a crash |
| E2 | Network loss mid-write | Enable airplane mode, try to delete a cat | Either queues offline (SDK) or shows a clear network error, depending on operation |

---
For each ✅ result you capture, save the screenshot with a filename matching the test ID
(e.g. `C1_add_cat_valid.png`) so your "Screenshots of Implemented Features" evidence is easy
to map back to this plan.
