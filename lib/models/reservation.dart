import 'package:cloud_firestore/cloud_firestore.dart';
import 'request_status.dart';

class Reservation {
  final String id;
  final String ownerId;
  final String ownerName;
  final String catId;
  final String catName;
  final String catBreed;
  final String vetId;
  final String vetName;
  final String visitType;
  final DateTime requestedAt;
  final String notes;
  final RequestStatus status;
  final String? providerNote;
  final String? queueNumber;
  final DateTime? checkedInAt;
  final Map<String, dynamic>? clinicalEmrPayload;
  final DateTime createdAt;
  final DateTime updatedAt;

  Reservation({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.catId,
    required this.catName,
    required this.catBreed,
    required this.vetId,
    required this.vetName,
    required this.visitType,
    required this.requestedAt,
    this.notes = '',
    this.status = RequestStatus.pending,
    this.providerNote,
    this.queueNumber,
    this.checkedInAt,
    this.clinicalEmrPayload,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'ownerName': ownerName,
      'catId': catId,
      'catName': catName,
      'catBreed': catBreed,
      'vetId': vetId,
      'vetName': vetName,
      'visitType': visitType,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'notes': notes,
      'status': status.toValue(),
      'providerNote': providerNote,
      if (queueNumber != null) 'queueNumber': queueNumber,
      if (checkedInAt != null) 'checkedInAt': Timestamp.fromDate(checkedInAt!),
      if (clinicalEmrPayload != null) 'clinicalEmrPayload': clinicalEmrPayload,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory Reservation.fromMap(String id, Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      return DateTime.now();
    }

    DateTime? parseOptionalDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      return null;
    }

    return Reservation(
      id: id,
      ownerId: (map['ownerId'] ?? '').toString(),
      ownerName: (map['ownerName'] ?? '').toString(),
      catId: (map['catId'] ?? '').toString(),
      catName: (map['catName'] ?? '').toString(),
      catBreed: (map['catBreed'] ?? '').toString(),
      vetId: (map['vetId'] ?? '').toString(),
      vetName: (map['vetName'] ?? '').toString(),
      visitType: (map['visitType'] ?? 'checkup').toString(),
      requestedAt: parseDate(map['requestedAt']),
      notes: (map['notes'] ?? '').toString(),
      status: RequestStatus.fromString(map['status'] as String?),
      providerNote: map['providerNote'] as String?,
      queueNumber: map['queueNumber']?.toString(),
      checkedInAt: parseOptionalDate(map['checkedInAt']),
      clinicalEmrPayload: map['clinicalEmrPayload'] is Map
          ? Map<String, dynamic>.from(map['clinicalEmrPayload'] as Map)
          : null,
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
    );
  }
}
