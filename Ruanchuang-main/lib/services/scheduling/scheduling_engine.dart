import '../../models/models.dart';

/// Stable interface for scheduling engines.
///
/// Today we use a heuristic implementation.
/// Future replacement point: a ML-based engine (Transformer + LSTM) can
/// implement the same interface, keeping input/output unchanged.
abstract class SchedulingEngine {
  SchedulingPlan plan(SchedulingRequest request);
}
