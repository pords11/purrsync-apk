import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      tz.initializeTimeZones();
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings settings = InitializationSettings(android: androidSettings);
      await _notificationsPlugin.initialize(settings);

      // Request notification permission on Android 13+
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Notification init error: $e');
    }
  }

  /// Schedules a vaccine reminder 1 day before [dueDate] at 09:00.
  /// Skips silently on web or if the reminder date is already in the past.
  static Future<void> scheduleVaccineReminder(
    String reminderId,
    String catName,
    DateTime dueDate,
  ) async {
    if (kIsWeb) return;

    try {
      final DateTime reminderDate = dueDate.subtract(const Duration(days: 1));
      final DateTime reminderDateTime = DateTime(reminderDate.year, reminderDate.month, reminderDate.day, 9, 0);
      if (reminderDateTime.isBefore(DateTime.now())) return;

      final int notifId = 'vax_$reminderId'.hashCode.abs();
      await _notificationsPlugin.cancel(notifId);

      await _notificationsPlugin.zonedSchedule(
        notifId,
        'Vaccine Reminder 🐾',
        'Upcoming vaccination for $catName on ${dueDate.toLocal().toString().split(' ')[0]}!',
        tz.TZDateTime.from(reminderDateTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'purrsync_alerts',
            'PurrSync Alerts',
            channelDescription: 'Reminders for cat vaccinations',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Error scheduling reminder: $e');
    }
  }

  /// Schedules an appointment reminder 1 hour before [startTime].
  static Future<void> scheduleAppointmentReminder(
    String id,
    String title,
    DateTime startTime,
  ) async {
    if (kIsWeb) return;
    try {
      final reminderTime = startTime.subtract(const Duration(hours: 1));
      if (reminderTime.isBefore(DateTime.now())) return;

      final int notifId = 'appt_$id'.hashCode.abs();
      await _notificationsPlugin.cancel(notifId);

      await _notificationsPlugin.zonedSchedule(
        notifId,
        'Appointment Reminder 🐾',
        title,
        tz.TZDateTime.from(reminderTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'purrsync_alerts',
            'PurrSync Alerts',
            channelDescription: 'Alerts and reminders for PurrSync appointments',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Error scheduling appointment reminder: $e');
    }
  }

  /// Cancels a scheduled reminder by its [id].
  static Future<void> cancelReminder(String id) async {
    if (kIsWeb) return;
    try {
      await _notificationsPlugin.cancel(id.hashCode.abs());
      await _notificationsPlugin.cancel('appt_$id'.hashCode.abs());
      await _notificationsPlugin.cancel('vax_$id'.hashCode.abs());
    } catch (e) {
      debugPrint('Error canceling reminder: $e');
    }
  }
}