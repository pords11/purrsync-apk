import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_role.dart';
import '../utils/time_utils.dart';

class ProviderProfile {
  final String id;
  final UserRole role;
  final String displayName;
  final String address;
  final String city;
  final String phone;
  final String bio;
  final String? specialty;
  final List<String> visitTypes;
  final String? openingHours; // Legacy fallback
  final String openTime; // "HH:mm" (24-hr)
  final String closeTime; // "HH:mm" (24-hr)
  final List<int> openDays; // 1 (Mon) .. 7 (Sun)
  final String hoursLabel;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProviderProfile({
    required this.id,
    required this.role,
    required this.displayName,
    required this.address,
    required this.city,
    required this.phone,
    this.bio = '',
    this.specialty,
    this.visitTypes = const [],
    this.openingHours,
    this.openTime = '08:00',
    this.closeTime = '18:00',
    this.openDays = const [1, 2, 3, 4, 5, 6],
    String? hoursLabel,
    this.active = true,
    required this.createdAt,
    required this.updatedAt,
  }) : hoursLabel = (hoursLabel != null && hoursLabel.isNotEmpty)
            ? hoursLabel
            : computeHoursLabel(openDays, openTime, closeTime);

  static String format12Hour(String hm) {
    try {
      final parts = hm.trim().split(':');
      if (parts.length >= 2) {
        int h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final period = h >= 12 ? 'PM' : 'AM';
        if (h == 0) {
          h = 12;
        } else if (h > 12) {
          h -= 12;
        }
        final minStr = m.toString().padLeft(2, '0');
        return '$h:$minStr $period';
      }
    } catch (_) {}
    return hm;
  }

  static String computeHoursLabel(List<int> days, String open, String close) {
    final dLabel = TimeUtils.daysLabel(days);
    final oLabel = format12Hour(open);
    final cLabel = format12Hour(close);
    return '$dLabel - $oLabel - $cLabel';
  }

  Map<String, dynamic> toMap() {
    return {
      'role': role.toValue(),
      'displayName': displayName,
      'address': address,
      'city': city,
      'phone': phone,
      'bio': bio,
      'specialty': specialty,
      'visitTypes': visitTypes,
      'openingHours': openingHours,
      'openTime': openTime,
      'closeTime': closeTime,
      'openDays': openDays,
      'hoursLabel': hoursLabel,
      'active': active,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'displayName': displayName,
      'address': address,
      'city': city,
      'phone': phone,
      'bio': bio,
      'specialty': specialty,
      'visitTypes': visitTypes,
      'openingHours': openingHours,
      'openTime': openTime,
      'closeTime': closeTime,
      'openDays': openDays,
      'hoursLabel': hoursLabel,
      'active': active,
      'updatedAt': Timestamp.now(),
    };
  }

  factory ProviderProfile.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      return DateTime.now();
    }

    final rawRole = map['role'] as String?;
    final role = UserRole.fromString(rawRole);

    final openT = (map['openTime'] ?? '08:00').toString();
    final closeT = (map['closeTime'] ?? '18:00').toString();
    final rawDays = map['openDays'] as List<dynamic>?;
    final openD = rawDays != null
        ? rawDays.map((e) => int.tryParse(e.toString()) ?? 1).toList()
        : const [1, 2, 3, 4, 5, 6];

    final storedHoursLabel = (map['hoursLabel'] ?? '').toString();
    final fallbackOpening = map['openingHours'] as String?;

    final resolvedHoursLabel = storedHoursLabel.isNotEmpty
        ? storedHoursLabel
        : (fallbackOpening != null && fallbackOpening.isNotEmpty
            ? fallbackOpening
            : computeHoursLabel(openD, openT, closeT));

    return ProviderProfile(
      id: id,
      role: role,
      displayName: (map['displayName'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      bio: (map['bio'] ?? '').toString(),
      specialty: map['specialty'] as String?,
      visitTypes: (map['visitTypes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      openingHours: fallbackOpening,
      openTime: openT,
      closeTime: closeT,
      openDays: openD,
      hoursLabel: resolvedHoursLabel,
      active: map['active'] is bool ? map['active'] as bool : true,
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
    );
  }
}
