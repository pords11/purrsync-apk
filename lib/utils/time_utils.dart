import 'package:flutter/material.dart';
import '../models/provider_profile.dart';

class TimeUtils {
  static const List<String> dayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Parses 24-hour "HH:mm" to TimeOfDay.
  static TimeOfDay parseHm(String hm) {
    try {
      final parts = hm.trim().split(':');
      if (parts.length >= 2) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        return TimeOfDay(hour: h, minute: m);
      }
    } catch (_) {}
    return const TimeOfDay(hour: 8, minute: 0);
  }

  /// Converts TimeOfDay to 24-hour "HH:mm".
  static String toHm(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Formats 24-hour "HH:mm" for display (e.g. "8:00 AM").
  static String labelHm(BuildContext context, String hm) {
    final t = parseHm(hm);
    return t.format(context);
  }

  /// Formats weekday ints (1=Mon ... 7=Sun) to readable string like "Mon-Sat".
  static String daysLabel(List<int> days) {
    if (days.isEmpty) return 'Mon-Sat';
    final sorted = days.toSet().toList()..sort();
    if (sorted.length == 7) return 'Daily (Mon-Sun)';
    if (sorted.length == 6 &&
        sorted[0] == 1 &&
        sorted[1] == 2 &&
        sorted[2] == 3 &&
        sorted[3] == 4 &&
        sorted[4] == 5 &&
        sorted[5] == 6) {
      return 'Mon-Sat';
    }
    if (sorted.length == 5 &&
        sorted[0] == 1 &&
        sorted[1] == 2 &&
        sorted[2] == 3 &&
        sorted[3] == 4 &&
        sorted[4] == 5) {
      return 'Mon-Fri';
    }
    return sorted.map((d) => (d >= 1 && d <= 7) ? dayNames[d - 1] : '').where((s) => s.isNotEmpty).join(', ');
  }

  /// Validates if a requested appointment [when] falls within [p]'s operating hours
  /// and open days, accounting for service duration.
  static bool isWithinHours(DateTime when, ProviderProfile p, {int durationMinutes = 0}) {
    final days = p.openDays.isNotEmpty ? p.openDays : [1, 2, 3, 4, 5, 6];
    if (!days.contains(when.weekday)) {
      return false;
    }

    final open = parseHm(p.openTime.isNotEmpty ? p.openTime : '08:00');
    final close = parseHm(p.closeTime.isNotEmpty ? p.closeTime : '18:00');

    final startMinutes = when.hour * 60 + when.minute;
    final endMinutes = startMinutes + durationMinutes;

    final openMinutes = open.hour * 60 + open.minute;
    final closeMinutes = close.hour * 60 + close.minute;

    return startMinutes >= openMinutes && endMinutes <= closeMinutes;
  }
}
