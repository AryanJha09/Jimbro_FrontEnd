import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/app_models.dart';

final workoutNotificationServiceProvider = Provider<WorkoutNotificationService>(
  (ref) => const MethodChannelWorkoutNotificationService(),
);

abstract class WorkoutNotificationService {
  Future<WorkoutReminderResult> scheduleWeeklyReminder(
    WorkoutScheduleEntry entry,
  );

  Future<void> cancelReminder(WorkoutScheduleEntry entry);
}

class WorkoutReminderResult {
  const WorkoutReminderResult({
    required this.status,
    required this.message,
  });

  final WorkoutReminderStatus status;
  final String message;
}

enum WorkoutReminderStatus {
  scheduled,
  denied,
  unavailable,
  cancelled,
}

class MethodChannelWorkoutNotificationService
    implements WorkoutNotificationService {
  const MethodChannelWorkoutNotificationService();

  static const _channel = MethodChannel('jimbro/workout_notifications');

  @override
  Future<WorkoutReminderResult> scheduleWeeklyReminder(
    WorkoutScheduleEntry entry,
  ) async {
    if (!entry.active) {
      await cancelReminder(entry);
      return const WorkoutReminderResult(
        status: WorkoutReminderStatus.cancelled,
        message: 'Reminder is off for this workout.',
      );
    }

    try {
      final granted =
          await _channel.invokeMethod<bool>('requestPermission') ?? false;
      if (!granted) {
        return const WorkoutReminderResult(
          status: WorkoutReminderStatus.denied,
          message:
              'Schedule saved. Reminders stay off until notifications are allowed.',
        );
      }

      final parts = _timeParts(entry.timeLabel);
      await _channel.invokeMethod<bool>(
        'scheduleWeeklyWorkout',
        {
          'id': _notificationId(entry),
          'title': 'JimBro workout',
          'body': 'Time for ${_displayName(entry)}.',
          'weekday': entry.weekday,
          'hour': parts.$1,
          'minute': parts.$2,
        },
      );
      return WorkoutReminderResult(
        status: WorkoutReminderStatus.scheduled,
        message:
            'Weekly reminder set for ${weekdayName(entry.weekday)} at ${entry.timeLabel}.',
      );
    } on MissingPluginException {
      return const WorkoutReminderResult(
        status: WorkoutReminderStatus.unavailable,
        message: 'Schedule saved. Local reminders are unavailable here.',
      );
    } on PlatformException catch (error) {
      final denied = error.code == 'permission_denied';
      return WorkoutReminderResult(
        status: denied
            ? WorkoutReminderStatus.denied
            : WorkoutReminderStatus.unavailable,
        message: denied
            ? 'Schedule saved. Reminders stay off until notifications are allowed.'
            : 'Schedule saved. Local reminders could not be scheduled.',
      );
    }
  }

  @override
  Future<void> cancelReminder(WorkoutScheduleEntry entry) async {
    try {
      await _channel.invokeMethod<bool>(
        'cancelWorkoutNotification',
        {'id': _notificationId(entry)},
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

String weekdayName(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => 'Monday',
  };
}

String _displayName(WorkoutScheduleEntry entry) {
  final name = entry.templateName.trim();
  return name.isEmpty ? 'your scheduled workout' : name;
}

String _notificationId(WorkoutScheduleEntry entry) {
  final id = entry.scheduleId ?? '${entry.weekday}-${entry.templateId ?? 0}';
  return 'workout-schedule-$id';
}

(int, int) _timeParts(String timeLabel) {
  final parts = timeLabel.split(':');
  final hour = parts.isEmpty ? 18 : int.tryParse(parts.first) ?? 18;
  final minute = parts.length < 2 ? 0 : int.tryParse(parts[1]) ?? 0;
  return (hour.clamp(0, 23), minute.clamp(0, 59));
}
