import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_role.dart';

class AppUser {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final DateTime createdAt;

  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.role = UserRole.owner,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'role': role.toValue(),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      return DateTime.now();
    }

    return AppUser(
      id: id,
      email: (map['email'] ?? '').toString(),
      fullName: (map['fullName'] ?? '').toString(),
      role: UserRole.fromString(map['role'] as String?),
      createdAt: parseDate(map['createdAt']),
    );
  }
}