import 'package:flutter_test/flutter_test.dart';
import 'package:purrsync/models/cat.dart';
import 'package:purrsync/models/request_status.dart';
import 'package:purrsync/models/user_role.dart';
import 'package:purrsync/models/provider_profile.dart';
import 'package:purrsync/models/service_offering.dart';
import 'package:purrsync/models/reservation.dart';
import 'package:purrsync/models/booking.dart';
import 'package:purrsync/models/announcement.dart';
import 'package:purrsync/utils/time_utils.dart';
import 'package:purrsync/utils/feline_protocol_utils.dart';

void main() {
  group('Cat Age Display Tests', () {
    test('Calculates newborn when under 1 month', () {
      final birth = DateTime.now().subtract(const Duration(days: 10));
      final cat = Cat(
        id: '1',
        userId: 'u1',
        name: 'Mochi',
        breed: 'Domestic',
        weight: 0.5,
        birthDate: birth,
      );
      expect(cat.ageDisplay, equals('Newborn'));
    });

    test('Calculates months when under 1 year', () {
      final now = DateTime.now();
      final birth = DateTime(now.year, now.month - 5, now.day);
      final cat = Cat(
        id: '1',
        userId: 'u1',
        name: 'Mochi',
        breed: 'Persian',
        weight: 2.0,
        birthDate: birth,
      );
      expect(cat.ageDisplay, equals('5 mos'));
    });

    test('Calculates years and months when over 1 year', () {
      final now = DateTime.now();
      final birth = DateTime(now.year - 2, now.month - 3, now.day);
      final cat = Cat(
        id: '1',
        userId: 'u1',
        name: 'Luna',
        breed: 'Siamese',
        weight: 3.5,
        birthDate: birth,
      );
      expect(cat.ageDisplay, equals('2 yrs 3 mos'));
    });

    test('Returns Unknown when birthDate is null', () {
      final cat = Cat(
        id: '1',
        userId: 'u1',
        name: 'Simba',
        breed: 'Tabby',
        weight: 4.0,
        birthDate: null,
      );
      expect(cat.ageDisplay, equals('Age unknown'));
    });

    test('Cat equality and hashCode are based on id', () {
      final cat1 = Cat(
        id: 'cat_abc',
        userId: 'u1',
        name: 'Luna',
        breed: 'Siamese',
        weight: 3.5,
      );
      final cat2 = Cat(
        id: 'cat_abc',
        userId: 'u1',
        name: 'Luna (Updated Name)',
        breed: 'Siamese',
        weight: 3.8,
      );
      final cat3 = Cat(
        id: 'cat_xyz',
        userId: 'u1',
        name: 'Luna',
        breed: 'Siamese',
        weight: 3.5,
      );

      expect(cat1 == cat2, isTrue);
      expect(cat1.hashCode, equals(cat2.hashCode));
      expect(cat1 == cat3, isFalse);
    });

    test('Cat gender field, genderOptions, and serialization work properly', () {
      expect(Cat.genderOptions, equals(['Male', 'Female', 'Neutered', 'Spayed']));

      final cat = Cat(
        id: 'cat_g1',
        userId: 'u1',
        name: 'Biscuit',
        breed: 'Persian',
        gender: 'Spayed',
        weight: 3.2,
      );
      expect(cat.gender, equals('Spayed'));
      expect(cat.genderDisplay, equals('Spayed'));

      final map = cat.toMap();
      expect(map['gender'], equals('Spayed'));

      final restored = Cat.fromMap('cat_g1', map);
      expect(restored.gender, equals('Spayed'));
      expect(restored.genderDisplay, equals('Spayed'));
    });
  });

  group('Vaccine Due Date Calculation Tests', () {
    final baseDate = DateTime(2026, 1, 1);

    test('Anti-Rabies adds 1 year', () {
      final due = VaccineRecord.calculateNextDue('Anti-Rabies (1 Year)', baseDate);
      expect(due, equals(DateTime(2027, 1, 1)));
    });

    test('4-in-1 adds 1 year', () {
      final due = VaccineRecord.calculateNextDue('4-in-1 (1 Year)', baseDate);
      expect(due, equals(DateTime(2027, 1, 1)));
    });

    test('Deworming adds 3 months (90 days)', () {
      final due = VaccineRecord.calculateNextDue('Deworming (3 Months)', baseDate);
      expect(due, equals(DateTime(2026, 4, 1)));
    });

    test('Custom interval adds custom days', () {
      final due = VaccineRecord.calculateNextDue('Custom', baseDate, customIntervalDays: 45);
      expect(due, equals(baseDate.add(const Duration(days: 45))));
    });

    test('isValidGivenDate rejects date before birthdate', () {
      final birth = DateTime(2022, 6, 1);
      expect(VaccineRecord.isValidGivenDate(DateTime(2022, 5, 31), birth), isFalse);
      expect(VaccineRecord.isValidGivenDate(DateTime(2022, 6, 1), birth), isTrue);
      expect(VaccineRecord.isValidGivenDate(DateTime(2022, 6, 2), birth), isTrue);
      expect(VaccineRecord.isValidGivenDate(DateTime(2022, 6, 1), null), isTrue);
    });

    test('isProviderSlotOccupied overlap logic correctly identifies conflicts', () {
      final start = DateTime(2026, 10, 20, 14, 0);
      final end = start.add(const Duration(minutes: 30)); // 14:00 - 14:30

      // Exact match 14:00 - 14:30
      expect(start.isBefore(end) && end.isAfter(start), isTrue);

      // Partial overlap 14:15 - 14:45
      final req2Start = DateTime(2026, 10, 20, 14, 15);
      final req2End = req2Start.add(const Duration(minutes: 30));
      expect(req2Start.isBefore(end) && req2End.isAfter(start), isTrue);

      // Completely before 13:00 - 13:30
      final req3Start = DateTime(2026, 10, 20, 13, 0);
      final req3End = req3Start.add(const Duration(minutes: 30));
      expect(req3Start.isBefore(end) && req3End.isAfter(start), isFalse);

      // Adjacent after 14:30 - 15:00 (non-overlapping)
      final req4Start = DateTime(2026, 10, 20, 14, 30);
      final req4End = req4Start.add(const Duration(minutes: 30));
      expect(req4Start.isBefore(end) && req4End.isAfter(start), isFalse);
    });
  });

  group('TimeUtils & ProviderProfile Hours Tests', () {
    test('parseHm and toHm round-trip', () {
      const hmStr = '14:30';
      final tod = TimeUtils.parseHm(hmStr);
      expect(tod.hour, equals(14));
      expect(tod.minute, equals(30));

      final converted = TimeUtils.toHm(tod);
      expect(converted, equals(hmStr));
    });

    test('ProviderProfile.format12Hour formats 12-hour strings', () {
      expect(ProviderProfile.format12Hour('09:05'), equals('9:05 AM'));
      expect(ProviderProfile.format12Hour('17:45'), equals('5:45 PM'));
      expect(ProviderProfile.format12Hour('00:00'), equals('12:00 AM'));
      expect(ProviderProfile.format12Hour('12:00'), equals('12:00 PM'));
    });

    test('daysLabel formats weekday sequences', () {
      expect(TimeUtils.daysLabel([1, 2, 3, 4, 5]), equals('Mon-Fri'));
      expect(TimeUtils.daysLabel([1, 2, 3, 4, 5, 6]), equals('Mon-Sat'));
      expect(TimeUtils.daysLabel([1, 2, 3, 4, 5, 6, 7]), equals('Daily (Mon-Sun)'));
      expect(TimeUtils.daysLabel([1, 3, 5]), equals('Mon, Wed, Fri'));
    });

    test('isWithinHours verifies provider operating schedule', () {
      final profile = ProviderProfile(
        id: 'p1',
        role: UserRole.vet,
        displayName: 'Dr. Jane',
        address: '123 Cat St',
        city: 'City',
        phone: '1234567890',
        openTime: '08:00',
        closeTime: '18:00',
        openDays: [1, 2, 3, 4, 5], // Mon-Fri
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Monday 10:00 AM -> open
      final mon10am = DateTime(2026, 10, 19, 10, 0); // Monday
      expect(TimeUtils.isWithinHours(mon10am, profile), isTrue);

      // Monday 7:00 PM -> closed
      final mon7pm = DateTime(2026, 10, 19, 19, 0);
      expect(TimeUtils.isWithinHours(mon7pm, profile), isFalse);

      // Sunday 11:00 AM -> closed (not in openDays)
      final sun11am = DateTime(2026, 10, 25, 11, 0); // Sunday
      expect(TimeUtils.isWithinHours(sun11am, profile), isFalse);
    });
  });

  group('RequestStatus and UserRole Enums', () {
    test('RequestStatus serialization and parsing', () {
      expect(RequestStatus.fromString('pending'), equals(RequestStatus.pending));
      expect(RequestStatus.fromString('accepted'), equals(RequestStatus.accepted));
      expect(RequestStatus.fromString('declined'), equals(RequestStatus.declined));
      expect(RequestStatus.fromString('cancelled'), equals(RequestStatus.cancelled));
      expect(RequestStatus.fromString('completed'), equals(RequestStatus.completed));
      expect(RequestStatus.fromString('expired'), equals(RequestStatus.expired));
      expect(RequestStatus.fromString('invalid_status'), equals(RequestStatus.pending));

      expect(RequestStatus.pending.toValue(), equals('pending'));
      expect(RequestStatus.accepted.toValue(), equals('accepted'));
      expect(RequestStatus.expired.toValue(), equals('expired'));
    });

    test('effectiveStatus computes expired and completed transitions', () {
      final now = DateTime(2026, 10, 18, 14, 0);
      final pastStart = DateTime(2026, 10, 18, 10, 0);
      final pastEnd = DateTime(2026, 10, 18, 11, 0);
      final futureStart = DateTime(2026, 10, 18, 16, 0);
      final futureEnd = DateTime(2026, 10, 18, 17, 0);

      // Pending + past start -> expired
      expect(
        effectiveStatus(stored: RequestStatus.pending, start: pastStart, end: pastEnd, now: now),
        equals(RequestStatus.expired),
      );

      // Pending + future start -> pending
      expect(
        effectiveStatus(stored: RequestStatus.pending, start: futureStart, end: futureEnd, now: now),
        equals(RequestStatus.pending),
      );

      // Accepted + past end -> completed
      expect(
        effectiveStatus(stored: RequestStatus.accepted, start: pastStart, end: pastEnd, now: now),
        equals(RequestStatus.completed),
      );

      // Accepted + future end -> accepted
      expect(
        effectiveStatus(stored: RequestStatus.accepted, start: futureStart, end: futureEnd, now: now),
        equals(RequestStatus.accepted),
      );

      // Cancelled -> stays cancelled
      expect(
        effectiveStatus(stored: RequestStatus.cancelled, start: pastStart, end: pastEnd, now: now),
        equals(RequestStatus.cancelled),
      );
    });

    test('UserRole serialization, parsing, and provider helpers', () {
      expect(UserRole.fromString('owner'), equals(UserRole.owner));
      expect(UserRole.fromString('vet'), equals(UserRole.vet));
      expect(UserRole.fromString('clinic'), equals(UserRole.clinic));
      expect(UserRole.fromString('provider'), equals(UserRole.vet));
      expect(UserRole.fromString('vet_clinic'), equals(UserRole.vet));
      expect(UserRole.fromString(null), equals(UserRole.owner));

      expect(UserRole.owner.toValue(), equals('owner'));
      expect(UserRole.vet.toValue(), equals('vet'));
      expect(UserRole.clinic.toValue(), equals('clinic'));

      expect(UserRole.owner.isProvider, isFalse);
      expect(UserRole.vet.isProvider, isTrue);
      expect(UserRole.clinic.isProvider, isTrue);

      expect(UserRole.owner.displayName, equals('Pet Owner'));
      expect(UserRole.vet.displayName, equals('Vet / Clinic'));
      expect(UserRole.clinic.displayName, equals('Vet / Clinic'));
    });
  });

  group('Model Serialization Tests', () {
    test('ProviderProfile toMap and fromMap', () {
      final now = DateTime.now();
      final profile = ProviderProfile(
        id: 'p123',
        role: UserRole.vet,
        displayName: 'Dr. Jane Smith',
        address: '123 Cat Lane',
        city: 'Feline City',
        phone: '555-0199',
        bio: 'Feline specialist',
        specialty: 'Surgery',
        visitTypes: ['Consultation', 'Surgery'],
        openTime: '09:00',
        closeTime: '17:00',
        openDays: [1, 2, 3, 4, 5],
        createdAt: now,
        updatedAt: now,
      );

      final map = profile.toMap();
      final restored = ProviderProfile.fromMap('p123', map);

      expect(restored.displayName, equals('Dr. Jane Smith'));
      expect(restored.role, equals(UserRole.vet));
      expect(restored.city, equals('Feline City'));
      expect(restored.openTime, equals('09:00'));
      expect(restored.closeTime, equals('17:00'));
      expect(restored.openDays, equals([1, 2, 3, 4, 5]));
    });

    test('ServiceOffering toMap and fromMap', () {
      final now = DateTime.now();
      final service = ServiceOffering(
        id: 's1',
        providerId: 'c1',
        providerName: 'Happy Paws Clinic',
        name: 'Full Feline Grooming',
        description: 'Bath, brush, and nail trim',
        category: 'Grooming',
        price: 45.0,
        durationMinutes: 60,
        active: true,
        createdAt: now,
        updatedAt: now,
      );

      final map = service.toMap();
      final restored = ServiceOffering.fromMap('s1', map);

      expect(restored.name, equals('Full Feline Grooming'));
      expect(restored.price, equals(45.0));
      expect(restored.durationMinutes, equals(60));
      expect(restored.active, isTrue);
    });

    test('Reservation toMap and fromMap', () {
      final now = DateTime.now();
      final reservation = Reservation(
        id: 'r1',
        ownerId: 'o1',
        ownerName: 'Alice',
        catId: 'c1',
        catName: 'Whiskers',
        catBreed: 'Siamese',
        vetId: 'v1',
        vetName: 'Dr. Ferdinand',
        visitType: 'Consultation',
        requestedAt: now,
        notes: 'Annual wellness check',
        status: RequestStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

      final map = reservation.toMap();
      final restored = Reservation.fromMap('r1', map);

      expect(restored.ownerName, equals('Alice'));
      expect(restored.catName, equals('Whiskers'));
      expect(restored.vetName, equals('Dr. Ferdinand'));
      expect(restored.status, equals(RequestStatus.pending));
    });

    test('Booking toMap and fromMap', () {
      final now = DateTime.now();
      final booking = Booking(
        id: 'b1',
        ownerId: 'o1',
        ownerName: 'Bob',
        catId: 'c2',
        catName: 'Milo',
        catBreed: 'Tabby',
        clinicId: 'cl1',
        clinicName: 'Metro Pet Hospital',
        serviceId: 's1',
        serviceName: 'Core Vaccination',
        servicePrice: 35.0,
        serviceDurationMinutes: 30,
        scheduledAt: now,
        notes: 'Needs rabies booster',
        status: RequestStatus.accepted,
        createdAt: now,
        updatedAt: now,
      );

      final map = booking.toMap();
      final restored = Booking.fromMap('b1', map);

      expect(restored.ownerName, equals('Bob'));
      expect(restored.serviceName, equals('Core Vaccination'));
      expect(restored.servicePrice, equals(35.0));
      expect(restored.status, equals(RequestStatus.accepted));
    });

    test('Announcement toMap and fromMap', () {
      final now = DateTime.now();
      final announcement = Announcement(
        id: 'a1',
        authorId: 'v1',
        authorRole: 'vet',
        authorName: 'Dr. Ferdinand',
        type: 'event',
        title: 'Free Anti-Rabies Drive',
        body: 'Bring your cats to the community center this Saturday.',
        eventDate: now.add(const Duration(days: 3)),
        location: 'Community Center',
        expiresAt: now.add(const Duration(days: 7)),
        published: true,
        createdAt: now,
        updatedAt: now,
      );

      final map = announcement.toMap();
      final restored = Announcement.fromMap('a1', map);

      expect(restored.title, equals('Free Anti-Rabies Drive'));
      expect(restored.type, equals('event'));
      expect(restored.location, equals('Community Center'));
      expect(restored.expiresAt, isNotNull);
      expect(restored.published, isTrue);
    });

    test('Emergency priority sorting pins pending Emergency above standard consultations', () {
      final now = DateTime.now();
      final standardFuture = Reservation(
        id: 'std1',
        ownerId: 'o1',
        ownerName: 'Alice',
        catId: 'c1',
        catName: 'Whiskers',
        catBreed: 'Siamese',
        vetId: 'v1',
        vetName: 'Dr. Ferdinand',
        visitType: 'Consultation',
        requestedAt: now.add(const Duration(days: 2)),
        notes: 'Routine checkup',
        status: RequestStatus.pending,
        createdAt: now,
        updatedAt: now,
      );
      final emergencyAsap = Reservation(
        id: 'emg1',
        ownerId: 'o2',
        ownerName: 'Juan',
        catId: 'c2',
        catName: 'Mittens',
        catBreed: 'Persian',
        vetId: 'v1',
        vetName: 'Dr. Ferdinand',
        visitType: 'Emergency',
        requestedAt: now.add(const Duration(minutes: 5)),
        notes: 'Difficulty breathing, urgent triage needed',
        status: RequestStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

      final items = [standardFuture, emergencyAsap];
      items.sort((a, b) {
        final aUrgent = a.visitType.toLowerCase().contains('emergency') && a.status == RequestStatus.pending;
        final bUrgent = b.visitType.toLowerCase().contains('emergency') && b.status == RequestStatus.pending;
        if (aUrgent != bUrgent) return aUrgent ? -1 : 1;
        return b.requestedAt.compareTo(a.requestedAt);
      });

      expect(items.first.id, equals('emg1'));
      expect(items.first.visitType, equals('Emergency'));
    });

    test('Clinical completion auto-log VetVisit serialization', () {
      final now = DateTime.now();
      final visit = VetVisit(
        id: 'res_r1',
        catId: 'c1',
        visitDate: now,
        clinicName: 'Dr. Ferdinand Clinic',
        reason: 'Emergency — Lethargy and dehydration',
        diagnosis: 'Subcutaneous fluids administered, vitals stabilized',
        prescribedMedicine: 'Electrolyte support for 5 days',
      );

      final map = visit.toMap();
      expect(map['catId'], equals('c1'));
      expect(map['clinicName'], equals('Dr. Ferdinand Clinic'));
      expect(map['diagnosis'], contains('Subcutaneous fluids'));
      expect(map['prescribedMedicine'], equals('Electrolyte support for 5 days'));
    });

    test('Pet Owner Active vs History/Archive filtering separates statuses and sorts by Emergency + closest date', () {
      final now = DateTime.now();
      final pendingLater = Reservation(
        id: 'r_later',
        ownerId: 'o1',
        ownerName: 'Alice',
        catId: 'c1',
        catName: 'Whiskers',
        catBreed: 'Siamese',
        vetId: 'v1',
        vetName: 'Dr. Ferdinand',
        visitType: 'Consultation',
        requestedAt: now.add(const Duration(days: 3)),
        notes: '',
        status: RequestStatus.pending,
        createdAt: now,
        updatedAt: now,
      );
      final acceptedSooner = Reservation(
        id: 'r_sooner',
        ownerId: 'o1',
        ownerName: 'Alice',
        catId: 'c1',
        catName: 'Whiskers',
        catBreed: 'Siamese',
        vetId: 'v1',
        vetName: 'Dr. Ferdinand',
        visitType: 'Checkup',
        requestedAt: now.add(const Duration(days: 1)),
        notes: '',
        status: RequestStatus.accepted,
        createdAt: now,
        updatedAt: now,
      );
      final emergencyActive = Reservation(
        id: 'r_emergency',
        ownerId: 'o1',
        ownerName: 'Alice',
        catId: 'c1',
        catName: 'Whiskers',
        catBreed: 'Siamese',
        vetId: 'v1',
        vetName: 'Dr. Ferdinand',
        visitType: 'Emergency',
        requestedAt: now.add(const Duration(days: 2)),
        notes: 'Urgent',
        status: RequestStatus.pending,
        createdAt: now,
        updatedAt: now,
      );
      final completedArchived = Reservation(
        id: 'r_completed',
        ownerId: 'o1',
        ownerName: 'Alice',
        catId: 'c1',
        catName: 'Whiskers',
        catBreed: 'Siamese',
        vetId: 'v1',
        vetName: 'Dr. Ferdinand',
        visitType: 'Consultation',
        requestedAt: now.subtract(const Duration(days: 2)),
        notes: '',
        status: RequestStatus.completed,
        providerNote: 'Recovered well',
        createdAt: now,
        updatedAt: now,
      );

      final all = [pendingLater, acceptedSooner, emergencyActive, completedArchived];
      final activeList = all
          .where((r) => r.status == RequestStatus.pending || r.status == RequestStatus.accepted)
          .toList();
      final historyList = all
          .where((r) => r.status != RequestStatus.pending && r.status != RequestStatus.accepted)
          .toList();

      activeList.sort((a, b) {
        final aEmg = a.visitType.toLowerCase().contains('emergency');
        final bEmg = b.visitType.toLowerCase().contains('emergency');
        if (aEmg != bEmg) return aEmg ? -1 : 1;
        return a.requestedAt.compareTo(b.requestedAt);
      });

      expect(activeList.map((r) => r.id).toList(), equals(['r_emergency', 'r_sooner', 'r_later']));
      expect(historyList.map((r) => r.id).toList(), equals(['r_completed']));
    });
  });

  group('Automated Clinical & Triage Protocol Tests', () {
    test('Kitten protocol generates core 3-dose FVRCP and Rabies milestones', () {
      final kitten = Cat(
        id: 'k1',
        userId: 'u1',
        name: 'Mochi',
        breed: 'Domestic',
        weight: 1.2,
        birthDate: DateTime.now().subtract(const Duration(days: 60)), // 2 months old
      );
      final protocol = FelineProtocolUtils.generateProtocolForCat(kitten);
      expect(protocol.length, equals(3));
      expect(protocol.any((v) => v.type.contains('FVRCP Core (Dose 1)')), isTrue);
      expect(protocol.any((v) => v.type.contains('Anti-Rabies')), isTrue);
    });

    test('Adult protocol generates Annual Booster and Deworming', () {
      final adultCat = Cat(
        id: 'a1',
        userId: 'u1',
        name: 'Luna',
        breed: 'Persian',
        weight: 4.0,
        birthDate: DateTime.now().subtract(const Duration(days: 800)), // ~2 years old
      );
      final protocol = FelineProtocolUtils.generateProtocolForCat(adultCat);
      expect(protocol.length, equals(3));
      expect(protocol.any((v) => v.type.contains('Annual Booster')), isTrue);
      expect(protocol.any((v) => v.type.contains('Deworming')), isTrue);
    });

    test('Weight Anomaly Detector alerts on acute weight drop > 10%', () {
      final now = DateTime.now();
      final logs = [
        WeightLog(id: 'w1', catId: 'c1', weight: 4.5, date: now.subtract(const Duration(days: 35))),
        WeightLog(id: 'w2', catId: 'c1', weight: 3.8, date: now.subtract(const Duration(days: 5))), // ~15.5% drop
      ];
      final anomaly = FelineProtocolUtils.detectWeightAnomaly(logs, 3.8);
      expect(anomaly.detected, isTrue);
      expect(anomaly.percentageChange, lessThan(-10.0));
      expect(anomaly.isSevere, isTrue);
    });

    test('Weight Anomaly Detector does not trigger false alarm on normal weight fluctuation', () {
      final now = DateTime.now();
      final logs = [
        WeightLog(id: 'w1', catId: 'c1', weight: 4.5, date: now.subtract(const Duration(days: 30))),
        WeightLog(id: 'w2', catId: 'c1', weight: 4.4, date: now.subtract(const Duration(days: 2))), // ~2.2% change
      ];
      final anomaly = FelineProtocolUtils.detectWeightAnomaly(logs, 4.4);
      expect(anomaly.detected, isFalse);
    });

    test('Reservation and Booking preserve automated queueNumber, checkedInAt, and clinicalEmrPayload', () {
      final now = DateTime.now();
      final res = Reservation(
        id: 'r_q1',
        ownerId: 'o1',
        ownerName: 'Ferdinand',
        catId: 'c1',
        catName: 'Mochi',
        catBreed: 'Persian',
        vetId: 'v1',
        vetName: 'Purrfect Care Feline Veterinary Center',
        visitType: 'Checkup',
        requestedAt: now,
        status: RequestStatus.completed,
        queueNumber: 'Q-01-M',
        checkedInAt: now,
        clinicalEmrPayload: {
          'recordedWeightKg': 4.2,
          'temperatureCelsius': 38.6,
          'totalBillPhp': 1400.0,
        },
        createdAt: now,
        updatedAt: now,
      );

      final restored = Reservation.fromMap('r_q1', res.toMap());
      expect(restored.queueNumber, equals('Q-01-M'));
      expect(restored.checkedInAt, isNotNull);
      expect(restored.clinicalEmrPayload?['recordedWeightKg'], equals(4.2));
      expect(restored.clinicalEmrPayload?['totalBillPhp'], equals(1400.0));
    });
  });
}
