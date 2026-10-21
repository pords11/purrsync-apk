import 'package:cloud_firestore/cloud_firestore.dart';
import 'request_status.dart';

class Booking {
  final String id;
  final String ownerId;
  final String ownerName;
  final String catId;
  final String catName;
  final String catBreed;
  final String clinicId;
  final String clinicName;
  final String serviceId;
  final String serviceName;
  final double servicePrice;
  final int serviceDurationMinutes;
  final DateTime scheduledAt;
  final String notes;
  final RequestStatus status;
  final String? providerNote;
  final String? queueNumber;
  final DateTime? checkedInAt;
  final Map<String, dynamic>? clinicalEmrPayload;
  final DateTime createdAt;
  final DateTime updatedAt;

  Booking({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.catId,
    required this.catName,
    required this.catBreed,
    required this.clinicId,
    required this.clinicName,
    required this.serviceId,
    required this.serviceName,
    required this.servicePrice,
    required this.serviceDurationMinutes,
    required this.scheduledAt,
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
      'clinicId': clinicId,
      'clinicName': clinicName,
      'serviceId': serviceId,
      'serviceName': serviceName,
      'servicePrice': servicePrice,
      'serviceDurationMinutes': serviceDurationMinutes,
      'scheduledAt': Timestamp.fromDate(scheduledAt),
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

  factory Booking.fromMap(String id, Map<String, dynamic> map) {
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

    return Booking(
      id: id,
      ownerId: (map['ownerId'] ?? '').toString(),
      ownerName: (map['ownerName'] ?? '').toString(),
      catId: (map['catId'] ?? '').toString(),
      catName: (map['catName'] ?? '').toString(),
      catBreed: (map['catBreed'] ?? '').toString(),
      clinicId: (map['clinicId'] ?? '').toString(),
      clinicName: (map['clinicName'] ?? '').toString(),
      serviceId: (map['serviceId'] ?? '').toString(),
      serviceName: (map['serviceName'] ?? '').toString(),
      servicePrice: (map['servicePrice'] is num) ? (map['servicePrice'] as num).toDouble() : 0.0,
      serviceDurationMinutes: (map['serviceDurationMinutes'] is num) ? (map['serviceDurationMinutes'] as num).toInt() : 30,
      scheduledAt: parseDate(map['scheduledAt']),
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
