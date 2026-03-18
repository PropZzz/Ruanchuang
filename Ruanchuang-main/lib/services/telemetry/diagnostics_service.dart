import 'package:flutter/foundation.dart';

class IcsTransferRecord {
  final DateTime at;
  final bool ok;
  final String action; // import/export
  final int count;
  final String? path;
  final String? error;

  const IcsTransferRecord({
    required this.at,
    required this.ok,
    required this.action,
    required this.count,
    this.path,
    this.error,
  });
}

class AppDiagnostics extends ChangeNotifier {
  int replanTriggers = 0;

  Duration? lastSchedulePlanCost;
  DateTime? lastSchedulePlanAt;
  String? lastSchedulePlanReason;

  IcsTransferRecord? lastIcsExport;
  IcsTransferRecord? lastIcsImport;

  void bumpReplan({required String reason}) {
    replanTriggers++;
    lastSchedulePlanReason = reason;
    notifyListeners();
  }

  void recordPlan({
    required Duration cost,
    required String reason,
  }) {
    lastSchedulePlanCost = cost;
    lastSchedulePlanAt = DateTime.now();
    lastSchedulePlanReason = reason;
    notifyListeners();
  }

  void recordIcsExport({
    required bool ok,
    required int count,
    String? path,
    String? error,
  }) {
    lastIcsExport = IcsTransferRecord(
      at: DateTime.now(),
      ok: ok,
      action: 'export',
      count: count,
      path: path,
      error: error,
    );
    notifyListeners();
  }

  void recordIcsImport({
    required bool ok,
    required int count,
    String? error,
  }) {
    lastIcsImport = IcsTransferRecord(
      at: DateTime.now(),
      ok: ok,
      action: 'import',
      count: count,
      error: error,
    );
    notifyListeners();
  }
}