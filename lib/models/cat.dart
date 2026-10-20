import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Cat {
  String id;
  String userId;
  String name;
  String breed;
  double weight;
  DateTime? birthDate;

  /// One of [Cat.genderOptions]. Empty string for legacy records without gender.
  String gender;
  String? imageBase64;
  String? imageUrl;
  List<WeightLog> weightLogs;
  List<VaccineRecord> vaccines;
  List<VetVisit> vetVisits;

  /// Allowed values for [gender].
  static const List<String> genderOptions = ['Male', 'Female', 'Neutered', 'Spayed'];

  /// Human-readable gender, falling back to 'Not specified'.
  String get genderDisplay => gender.trim().isEmpty ? 'Not specified' : gender;

  @override
  bool operator ==(Object other) => other is Cat && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Cat({
    required this.id,
    required this.userId,
    required this.name,
    required this.breed,
    required this.weight,
    this.birthDate,
    this.gender = '',
    this.imageBase64,
    this.imageUrl,
    this.weightLogs = const [],
    this.vaccines = const [],
    this.vetVisits = const [],
  });

  int get age {
    if (birthDate == null) return 0;
    final now = DateTime.now();
    return now.difference(birthDate!).inDays ~/ 365;
  }

  String get ageDisplay {
    if (birthDate == null) return 'Age unknown';
    final now = DateTime.now();
    if (birthDate!.isAfter(now)) return 'Age unknown';

    int months = (now.year - birthDate!.year) * 12 + (now.month - birthDate!.month);
    if (now.day < birthDate!.day) {
      months--;
    }
    if (months <= 0) return 'Newborn';
    if (months < 12) {
      return months == 1 ? '1 mo' : '$months mos';
    }
    final years = months ~/ 12;
    final remainingMonths = months % 12;
    final yrStr = years == 1 ? '1 yr' : '$years yrs';
    if (remainingMonths == 0) return yrStr;
    final moStr = remainingMonths == 1 ? '1 mo' : '$remainingMonths mos';
    return '$yrStr $moStr';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'breed': breed,
      'weight': weight,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
      'gender': gender,
      'imageBase64': imageBase64,
      'imageUrl': imageUrl,
      'createdAt': DateTime.now(),
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'userId': userId,
      'name': name,
      'breed': breed,
      'weight': weight,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
      'gender': gender,
      'imageBase64': imageBase64,
      'imageUrl': imageUrl,
      'updatedAt': DateTime.now(),
    };
  }

  factory Cat.fromMap(String id, Map<String, dynamic> map) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      return null;
    }

    final imgBase64 = map['imageBase64'] as String?;
    final legacyImg = map['imageUrl'] as String?;

    return Cat(
      id: id,
      userId: map['userId'] ?? '',
      name: map['name'] ?? '',
      breed: map['breed'] ?? '',
      weight: (map['weight'] ?? 0).toDouble(),
      birthDate: parseDate(map['birthDate']),
      gender: (map['gender'] ?? '').toString(),
      imageBase64: imgBase64 ?? legacyImg,
      imageUrl: legacyImg,
    );
  }
}

class WeightLog {
  String id;
  String catId;
  double weight;
  DateTime date;
  String? notes;

  WeightLog({
    required this.id,
    required this.catId,
    required this.weight,
    required this.date,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'catId': catId,
      'weight': weight,
      'date': Timestamp.fromDate(date),
      'notes': notes,
    };
  }
}

class VaccineRecord {
  String id;
  String catId;
  String type;
  DateTime dateGiven;
  DateTime nextDueDate;
  String? clinicName;
  String? veterinarian;
  String? notes;

  VaccineRecord({
    required this.id,
    required this.catId,
    required this.type,
    required this.dateGiven,
    required this.nextDueDate,
    this.clinicName,
    this.veterinarian,
    this.notes,
  });

  String getStatus() {
    final now = DateTime.now();
    if (nextDueDate.isBefore(now)) return 'Overdue';
    if (nextDueDate.difference(now).inDays <= 30) return 'Upcoming';
    return 'Safe';
  }

  Color getStatusColor() {
    final status = getStatus();
    switch (status) {
      case 'Overdue':
        return Colors.red;
      case 'Upcoming':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  /// Validates that the dateGiven is not before the cat's birthdate.
  static bool isValidGivenDate(DateTime dateGiven, DateTime? birthDate) {
    if (birthDate == null) return true;
    final bDate = DateTime(birthDate.year, birthDate.month, birthDate.day);
    final gDate = DateTime(dateGiven.year, dateGiven.month, dateGiven.day);
    return !gDate.isBefore(bDate);
  }

  /// Calculates next due date based on type or customIntervalDays.
  static DateTime calculateNextDue(String type, DateTime dateGiven, {int? customIntervalDays}) {
    final lower = type.toLowerCase();
    if (lower.contains('custom')) {
      final days = (customIntervalDays != null && customIntervalDays > 0) ? customIntervalDays : 30;
      return dateGiven.add(Duration(days: days));
    }
    if (lower.contains('deworming')) {
      return dateGiven.add(const Duration(days: 90));
    }
    // Anti-rabies, 4-in-1, etc. -> 365 days
    return dateGiven.add(const Duration(days: 365));
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'catId': catId,
      'type': type,
      'dateGiven': Timestamp.fromDate(dateGiven),
      'nextDueDate': Timestamp.fromDate(nextDueDate),
      'clinicName': clinicName,
      'veterinarian': veterinarian,
      'notes': notes,
    };
  }
}

class VetVisit {
  String id;
  String catId;
  DateTime visitDate;
  String clinicName;
  String reason;
  String diagnosis;
  String? prescribedMedicine;
  DateTime? followUpDate;

  VetVisit({
    required this.id,
    required this.catId,
    required this.visitDate,
    required this.clinicName,
    required this.reason,
    required this.diagnosis,
    this.prescribedMedicine,
    this.followUpDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'catId': catId,
      'visitDate': Timestamp.fromDate(visitDate),
      'clinicName': clinicName,
      'reason': reason,
      'diagnosis': diagnosis,
      'prescribedMedicine': prescribedMedicine,
      'followUpDate': followUpDate != null ? Timestamp.fromDate(followUpDate!) : null,
    };
  }
}