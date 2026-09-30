import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/util/time_format.dart';
import '../domain/models.dart';

/// Schedules local notifications for tasks that have a due date.
abstract interface class Reminders {
  Future<void> init({void Function(String noteId)? onOpenNote});
  Future<bool> requestPermission();

  /// (Re)schedules the reminder of [task]; all-day tasks fire at [hour]:00.
  Future<void> schedule(TaskInfo task, {int hour = 9});
  Future<void> cancel(String taskId);
  Future<void> syncAll(List<TaskInfo> openTasks, {int hour = 9});
}

/// No-op implementation for tests and unsupported platforms.
class NoReminders implements Reminders {
  @override
  Future<void> init({void Function(String noteId)? onOpenNote}) async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> schedule(TaskInfo task, {int hour = 9}) async {}
  @override
  Future<void> cancel(String taskId) async {}
  @override
  Future<void> syncAll(List<TaskInfo> openTasks, {int hour = 9}) async {}
}

/// `flutter_local_notifications` backed reminders. Instants are scheduled in UTC (an absolute
/// moment), so no time-zone database has to be bundled and DST changes can't shift a reminder.
class LocalNotificationReminders implements Reminders {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _permissionAsked = false;

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Reminders for tasks found in your notes',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBanner: true),
  );

  /// Stable 31-bit id for a ULID (Android requires 32-bit ids).
  @visibleForTesting
  static int notificationId(String taskId) {
    var h = 0x811C9DC5;
    for (final c in taskId.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7FFFFFFF;
    }
    return h;
  }

  @override
  Future<void> init({void Function(String noteId)? onOpenNote}) async {
    if (kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final payload = r.payload;
          if (payload != null && payload.startsWith('note:')) onOpenNote?.call(payload.substring(5));
        },
      );
      _ready = true;
    } on Object catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    _permissionAsked = true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, badge: false, sound: true) ?? false;
    } on Object catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
    return false;
  }

  @override
  Future<void> schedule(TaskInfo task, {int hour = 9}) async {
    if (!_ready || task.done) return;
    final due = task.dueAt;
    if (due == null) return;
    final when = task.hasTime ? due : DateTime(due.year, due.month, due.day, hour);
    if (!when.isAfter(DateTime.now())) {
      await cancel(task.id);
      return;
    }
    if (!_permissionAsked) await requestPermission();
    try {
      await _plugin.zonedSchedule(
        id: notificationId(task.id),
        title: task.title,
        body: task.noteTitle == null || task.noteTitle!.isEmpty
            ? TimeFormat.dueLabel(due, DateTime.now(), hasTime: task.hasTime)
            : '${TimeFormat.dueLabel(due, DateTime.now(), hasTime: task.hasTime)} · ${task.noteTitle}',
        scheduledDate: tz.TZDateTime.from(when, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'note:${task.noteId}',
      );
    } on Object catch (e) {
      debugPrint('Could not schedule reminder: $e');
    }
  }

  @override
  Future<void> cancel(String taskId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: notificationId(taskId));
    } on Object catch (e) {
      debugPrint('Could not cancel reminder: $e');
    }
  }

  @override
  Future<void> syncAll(List<TaskInfo> openTasks, {int hour = 9}) async {
    if (!_ready) return;
    for (final t in openTasks) {
      await schedule(t, hour: hour);
    }
  }
}
