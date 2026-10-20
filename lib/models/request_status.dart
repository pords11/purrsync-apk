import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

enum RequestStatus {
  pending,
  accepted,
  declined,
  cancelled,
  completed,
  expired;

  String toValue() {
    switch (this) {
      case RequestStatus.pending:
        return 'pending';
      case RequestStatus.accepted:
        return 'accepted';
      case RequestStatus.declined:
        return 'declined';
      case RequestStatus.cancelled:
        return 'cancelled';
      case RequestStatus.completed:
        return 'completed';
      case RequestStatus.expired:
        return 'expired';
    }
  }

  String get label {
    switch (this) {
      case RequestStatus.pending:
        return 'Pending';
      case RequestStatus.accepted:
        return 'Accepted';
      case RequestStatus.declined:
        return 'Declined';
      case RequestStatus.cancelled:
        return 'Cancelled';
      case RequestStatus.completed:
        return 'Completed';
      case RequestStatus.expired:
        return 'Expired';
    }
  }

  Color get backgroundColor {
    switch (this) {
      case RequestStatus.pending:
        return AppTheme.statusWarningBg; // Due-soon amber soft tint
      case RequestStatus.accepted:
        return AppTheme.statusSafeBg; // Safe green soft tint
      case RequestStatus.declined:
        return AppTheme.statusDangerBg; // Overdue/Danger red soft tint
      case RequestStatus.cancelled:
        return const Color(0xFFF3F5F4); // Soft grey
      case RequestStatus.completed:
        return AppTheme.primarySubtle; // Soft teal
      case RequestStatus.expired:
        return const Color(0xFFEFEBE9); // Soft sand
    }
  }

  Color get textColor {
    switch (this) {
      case RequestStatus.pending:
        return AppTheme.statusWarning; // #F2A33A
      case RequestStatus.accepted:
        return AppTheme.statusSafe; // #3DAE7C
      case RequestStatus.declined:
        return AppTheme.statusDanger; // #E5534B
      case RequestStatus.cancelled:
        return const Color(0xFF6B7B78); // Muted slate
      case RequestStatus.completed:
        return AppTheme.primary; // #2A6F68
      case RequestStatus.expired:
        return const Color(0xFF795548); // Warm taupe
    }
  }

  Color get color => textColor;

  /// Morphing status badge chip (`250ms` easeOutCubic transition when status changes).
  Widget buildBadge({double fontSize = 12}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withValues(alpha: 0.22), width: 1),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Text(
          label,
          key: ValueKey<String>(label),
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  static RequestStatus fromString(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'accepted':
        return RequestStatus.accepted;
      case 'declined':
        return RequestStatus.declined;
      case 'cancelled':
        return RequestStatus.cancelled;
      case 'completed':
        return RequestStatus.completed;
      case 'expired':
        return RequestStatus.expired;
      case 'pending':
      default:
        return RequestStatus.pending;
    }
  }
}

/// Computes the effective display status without writing to Firestore.
/// - pending + start < now → expired
/// - accepted + end < now → completed
/// Otherwise returns stored.
RequestStatus effectiveStatus({
  required RequestStatus stored,
  required DateTime start,
  required DateTime end,
  required DateTime now,
}) {
  if (stored == RequestStatus.pending && start.isBefore(now)) {
    return RequestStatus.expired;
  }
  if (stored == RequestStatus.accepted && end.isBefore(now)) {
    return RequestStatus.completed;
  }
  return stored;
}
