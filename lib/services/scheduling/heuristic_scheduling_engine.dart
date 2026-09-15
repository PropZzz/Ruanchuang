import '../../models/models.dart';
import 'scheduler_core.dart';
import 'scheduling_engine.dart';

/// Compatibility adapter for callers that still select the heuristic engine.
class HeuristicSchedulingEngine implements SchedulingEngine {
  const HeuristicSchedulingEngine({SchedulerCore? core})
      : _core = core ?? const SchedulerCore();

  final SchedulerCore _core;

  @override
  SchedulingPlan plan(SchedulingRequest request) => _core.plan(request);
}
