import 'package:flutter/foundation.dart';

import 'bluetooth_service.dart';
import 'data_service.dart';
import 'local_data_service.dart';

import 'microtask_crystals/heuristic_microtask_crystal_engine.dart';
import 'microtask_crystals/microtask_crystal_engine.dart';
import 'reminders/reminder_service.dart';
import 'scheduling/heuristic_scheduling_engine.dart';
import 'scheduling/scheduling_engine.dart';
import 'team_collab/heuristic_team_collab_engine.dart';
import 'team_collab/team_collab_engine.dart';

import 'telemetry/app_log.dart';
import 'telemetry/diagnostics_service.dart';

/// Single place for wiring app-wide services.
class AppServices {
  static final DataService _defaultDataService = LocalDataService.instance;
  static DataService? _dataServiceOverride;
  static DataService get dataService =>
      _dataServiceOverride ?? _defaultDataService;

  static final SchedulingEngine schedulingEngine = HeuristicSchedulingEngine();

  static final MicroTaskCrystalEngine microTaskCrystalEngine =
      HeuristicMicroTaskCrystalEngine();

  static final TeamCollabEngine teamCollabEngine = HeuristicTeamCollabEngine();

  static final ReminderService _defaultReminderService = ReminderService();
  static ReminderService? _reminderServiceOverride;
  static ReminderService get reminderService =>
      _reminderServiceOverride ?? _defaultReminderService;

  static final BluetoothService bluetoothService = BluetoothService(
    dataService,
  );

  static final AppLogStore logStore = AppLogStore();
  static final AppDiagnostics diagnostics = AppDiagnostics();

  @visibleForTesting
  static void installTestOverrides({
    DataService? dataService,
    ReminderService? reminderService,
  }) {
    _dataServiceOverride = dataService;
    _reminderServiceOverride = reminderService;
  }

  @visibleForTesting
  static void resetForTests() {
    _reminderServiceOverride?.dispose();
    _defaultReminderService.dispose();
    _dataServiceOverride = null;
    _reminderServiceOverride = null;
  }

  /// Optional warm-up (loads local storage early).
  /// Returns true if successful, false otherwise.
  static Future<bool> prewarm() async {
    final sw = Stopwatch()..start();
    logStore.info('app', 'prewarm start');
    try {
      final entries = await dataService.getScheduleEntries();
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      await reminderService.rescheduleDay(day: day, entries: entries);
      await bluetoothService.initialize();
      sw.stop();
      logStore.info(
        'app',
        'prewarm done',
        data: {'ms': sw.elapsedMilliseconds, 'entries': entries.length},
      );
      return true;
    } catch (e, st) {
      sw.stop();
      logStore.error(
        'app',
        'prewarm failed',
        error: e,
        stackTrace: st,
        data: {'ms': sw.elapsedMilliseconds},
      );
      return false;
    }
  }
}
