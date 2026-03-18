import 'composite_data_service.dart';
import 'data_service.dart';
import 'remote_data_service.dart';

import 'local_data_service_io.dart'
    if (dart.library.html) 'local_data_service_web.dart';

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
  static final DataService dataService = CompositeDataService(
    local: LocalDataService.instance,
    remote: RemoteDataService.instance,
  );

  static final SchedulingEngine schedulingEngine = HeuristicSchedulingEngine();

  static final MicroTaskCrystalEngine microTaskCrystalEngine =
      HeuristicMicroTaskCrystalEngine();

  static final TeamCollabEngine teamCollabEngine = HeuristicTeamCollabEngine();

  static final ReminderService reminderService = ReminderService();

  static final AppLogStore logStore = AppLogStore();
  static final AppDiagnostics diagnostics = AppDiagnostics();

  /// Optional warm-up (loads local storage early).
  static Future<void> prewarm() async {
    final sw = Stopwatch()..start();
    logStore.info('app', 'prewarm start');
    try {
      final entries = await dataService.getScheduleEntries();
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      await reminderService.rescheduleDay(day: day, entries: entries);
      sw.stop();
      logStore.info(
        'app',
        'prewarm done',
        data: {'ms': sw.elapsedMilliseconds, 'entries': entries.length},
      );
    } catch (e, st) {
      sw.stop();
      logStore.error(
        'app',
        'prewarm failed',
        error: e,
        stackTrace: st,
        data: {'ms': sw.elapsedMilliseconds},
      );
      rethrow;
    }
  }
}
