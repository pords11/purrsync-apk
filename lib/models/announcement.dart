import 'package:cloud_firestore/cloud_firestore.dart';

class Announcement {
  final String id;
  final String authorId;
  final String authorRole; // vet, clinic
  final String authorName;
  final String type; // announcement, event
  final String title;
  final String body;
  final DateTime? eventDate;
  final String? location;
  final DateTime? expiresAt;
  final bool published;
  final DateTime createdAt;
  final DateTime updatedAt;

  Announcement({
    required this.id,
    required this.authorId,
    required this.authorRole,
    required this.authorName,
    required this.type,
    required this.title,
    required this.body,
    this.eventDate,
    this.location,
    this.expiresAt,
    this.published = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'authorRole': authorRole,
      'authorName': authorName,
      'type': type,
      'title': title,
      'body': body,
      'eventDate': eventDate != null ? Timestamp.fromDate(eventDate!) : null,
      'location': location,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'published': published,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'type': type,
      'title': title,
      'body': body,
      'eventDate': eventDate != null ? Timestamp.fromDate(eventDate!) : null,
      'location': location,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'published': published,
      'updatedAt': Timestamp.now(),
    };
  }

  factory Announcement.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      return null;
    }

    return Announcement(
      id: id,
      authorId: (map['authorId'] ?? '').toString(),
      authorRole: (map['authorRole'] ?? 'vet').toString(),
      authorName: (map['authorName'] ?? '').toString(),
      type: (map['type'] ?? 'announcement').toString(),
      title: (map['title'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      eventDate: parseNullableDate(map['eventDate']),
      location: map['location'] as String?,
      expiresAt: parseNullableDate(map['expiresAt']),
      published: map['published'] is bool ? map['published'] as bool : true,
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
    );
  }
}
