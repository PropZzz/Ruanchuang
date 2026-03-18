import 'package:flutter/material.dart';

import '../../services/app_services.dart';
import '../../services/composite_data_service.dart';
import '../../services/debug/storage_info.dart';
import '../../services/local_data_service.dart';
import '../../services/telemetry/app_log.dart';
import '../../services/telemetry/diagnostics_service.dart';
import '../../services/telemetry/platform/text_file_saver.dart';
import '../../utils/app_strings.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  Future<StorageInfo>? _storageFuture;

  @override
  void initState() {
    super.initState();
    _refreshStorage();
  }

  void _refreshStorage() {
    setState(() {
      _storageFuture = _loadStorageInfo();
    });
  }

  Future<StorageInfo> _loadStorageInfo() async {
    final ds = AppServices.dataService;
    if (ds is CompositeDataService && ds.local is LocalDataService) {
      return (ds.local as LocalDataService).debugStorageInfo();
    }
    if (ds is LocalDataService) {
      return ds.debugStorageInfo();
    }
    return const StorageInfo(exists: false, bytes: 0, backend: 'unknown');
  }

  String _typeLabel(Object? o) => o == null ? '-' : o.runtimeType.toString();

  Future<void> _exportLogs() async {
    final text = AppServices.logStore.exportText();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('.', '');
    final name = 'battleman_logs_$ts.txt';

    AppServices.logStore.info(
      'diagnostics',
      'export logs',
      data: {'fileName': name, 'bytes': text.length},
    );

    final res = await TextFileSaver.save(text, fileName: name);
    if (!mounted) return;

    final msg = res.error != null
        ? AppStrings.of(
            context,
            'diag_export_failed',
            params: {'error': res.error ?? ''},
          )
        : (res.path == null
            ? AppStrings.of(context, 'diag_export_ok')
            : AppStrings.of(
                context,
                'diag_export_ok_path',
                params: {'path': res.path ?? ''},
              ));

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Color _levelColor(AppLogLevel l) {
    switch (l) {
      case AppLogLevel.debug:
        return Colors.grey;
      case AppLogLevel.info:
        return Colors.blueGrey;
      case AppLogLevel.warn:
        return Colors.orange;
      case AppLogLevel.error:
        return Colors.red;
    }
  }

  String _backendLabel(BuildContext context, String backend) {
    if (backend == 'unknown') return AppStrings.of(context, 'common_unknown');
    return backend;
  }

  String _levelLabel(BuildContext context, AppLogLevel level) {
    switch (level) {
      case AppLogLevel.debug:
        return AppStrings.of(context, 'log_level_debug');
      case AppLogLevel.info:
        return AppStrings.of(context, 'log_level_info');
      case AppLogLevel.warn:
        return AppStrings.of(context, 'log_level_warn');
      case AppLogLevel.error:
        return AppStrings.of(context, 'log_level_error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = AppServices.dataService;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context, 'diag_title')),
        actions: [
          IconButton(
            tooltip: AppStrings.of(context, 'diag_tooltip_refresh'),
            onPressed: _refreshStorage,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: AppStrings.of(context, 'diag_tooltip_export_logs'),
            onPressed: _exportLogs,
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([AppServices.diagnostics, AppServices.logStore]),
        builder: (ctx, _) {
          final diag = AppServices.diagnostics;
          final logs = AppServices.logStore.entries;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle(AppStrings.of(context, 'diag_section_data')),
              _kv(
                AppStrings.of(context, 'diag_kv_data_service'),
                _typeLabel(ds),
              ),
              if (ds is CompositeDataService) ...[
                _kv(AppStrings.of(context, 'diag_kv_local'), _typeLabel(ds.local)),
                _kv(AppStrings.of(context, 'diag_kv_remote'), _typeLabel(ds.remote)),
              ],
              const SizedBox(height: 12),
              _sectionTitle(AppStrings.of(context, 'diag_section_storage')),
              FutureBuilder<StorageInfo>(
                future: _storageFuture,
                builder: (ctx2, snap) {
                  final v = snap.data;
                  if (v == null) {
                    return Text(AppStrings.of(ctx2, 'common_loading'));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv(
                        AppStrings.of(ctx2, 'diag_kv_backend'),
                        _backendLabel(ctx2, v.backend),
                      ),
                      _kv(
                        AppStrings.of(ctx2, 'diag_kv_exists'),
                        v.exists.toString(),
                      ),
                      _kv(
                        AppStrings.of(ctx2, 'diag_kv_bytes'),
                        v.bytes.toString(),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _sectionTitle(AppStrings.of(context, 'diag_section_perf')),
              _kv(
                AppStrings.of(context, 'diag_kv_replan_triggers'),
                diag.replanTriggers.toString(),
              ),
              _kv(
                AppStrings.of(context, 'diag_kv_last_plan_cost_ms'),
                diag.lastSchedulePlanCost?.inMilliseconds.toString() ?? '-',
              ),
              _kv(
                AppStrings.of(context, 'diag_kv_last_plan_at'),
                diag.lastSchedulePlanAt?.toIso8601String() ?? '-',
              ),
              _kv(
                AppStrings.of(context, 'diag_kv_last_plan_reason'),
                diag.lastSchedulePlanReason ?? '-',
              ),
              const SizedBox(height: 12),
              _sectionTitle(AppStrings.of(context, 'diag_section_ics')),
              _icsRow(AppStrings.of(context, 'diag_kv_last_export'), diag.lastIcsExport),
              _icsRow(AppStrings.of(context, 'diag_kv_last_import'), diag.lastIcsImport),
              const SizedBox(height: 12),
              _sectionTitle(AppStrings.of(context, 'diag_section_logs')),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      AppServices.logStore.clear();
                      AppServices.logStore.info('diagnostics', 'clear logs');
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: Text(AppStrings.of(context, 'diag_btn_clear')),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _exportLogs,
                    icon: const Icon(Icons.download),
                    label: Text(AppStrings.of(context, 'diag_btn_export')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: logs.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(AppStrings.of(context, 'diag_logs_empty')),
                          ),
                        ]
                      : logs
                          .reversed
                          .take(80)
                          .map(
                            (e) => ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              title: Text(
                                '[${_levelLabel(context, e.level)}] ${e.category}: ${e.message}',
                                style: TextStyle(color: _levelColor(e.level)),
                              ),
                              subtitle: Text(
                                '${e.at.toIso8601String()}${e.data.isEmpty ? '' : '  ${e.data}'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('$k: $v'),
      );

  Widget _icsRow(String label, IcsTransferRecord? r) {
    if (r == null) return _kv(label, '-');
    final status = r.ok
        ? AppStrings.of(context, 'common_ok')
        : AppStrings.of(context, 'common_fail');
    final parts = <String>[
      status,
      '${AppStrings.of(context, 'common_count')}: ${r.count}',
      '${AppStrings.of(context, 'common_at')}: ${r.at.toIso8601String()}',
      if (r.path != null)
        '${AppStrings.of(context, 'common_path')}: ${r.path}',
      if (r.error != null)
        '${AppStrings.of(context, 'common_error')}: ${r.error}',
    ];
    final s = parts.join('  ');
    return _kv(label, s);
  }
}
