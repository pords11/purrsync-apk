import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceOffering {
  final String id;
  final String providerId;
  final String providerName;
  final String name;
  final String description;
  final String category; // consultation, vaccination, grooming, boarding, surgery, other
  final double price;
  final int durationMinutes;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServiceOffering({
    required this.id,
    required this.providerId,
    required this.providerName,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.durationMinutes,
    this.active = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'providerId': providerId,
      'providerName': providerName,
      'name': name,
      'description': description,
      'category': category,
      'price': price,
      'durationMinutes': durationMinutes,
      'active': active,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'name': name,
      'description': description,
      'category': category,
      'price': price,
      'durationMinutes': durationMinutes,
      'active': active,
      'updatedAt': Timestamp.now(),
    };
  }

  factory ServiceOffering.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      return DateTime.now();
    }

    return ServiceOffering(
      id: id,
      providerId: (map['providerId'] ?? '').toString(),
      providerName: (map['providerName'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      category: (map['category'] ?? 'consultation').toString(),
      price: (map['price'] is num) ? (map['price'] as num).toDouble() : 0.0,
      durationMinutes: (map['durationMinutes'] is num) ? (map['durationMinutes'] as num).toInt() : 30,
      active: map['active'] is bool ? map['active'] as bool : true,
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
    );
  }
}
