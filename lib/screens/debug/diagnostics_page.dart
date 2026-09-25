import 'package:flutter/material.dart';

import '../../services/app_services.dart';
import '../../services/composite_data_service.dart';
import '../../services/debug/storage_info.dart';
import '../../services/local_data_service.dart';
import '../../services/telemetry/app_log.dart';
import '../../services/telemetry/diagnostics_service.dart';
import '../../services/telemetry/platform/text_file_saver.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_strings.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  Future<StorageInfo>? _storageFuture;
  final _searchController = TextEditingController();
  String _query = '';
  AppLogLevel? _levelFilter;

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  List<AppLogEntry> _filterLogs(List<AppLogEntry> logs) {
    final query = _query.trim().toLowerCase();
    return logs.reversed.take(80).where((entry) {
      if (_levelFilter != null && entry.level != _levelFilter) return false;
      if (query.isEmpty) return true;
      final searchable = [
        entry.category,
        entry.message,
        entry.data.toString(),
        entry.error ?? '',
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ds = AppServices.dataService;

    return Scaffold(
      backgroundColor: AppWindowTones.canvas(context, AppWindowTone.neutral),
      appBar: AppBar(
        title: const Text('系统诊断与运行健康'),
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
        animation: Listenable.merge([
          AppServices.diagnostics,
          AppServices.logStore,
        ]),
        builder: (ctx, _) {
          final diag = AppServices.diagnostics;
          final allLogs = AppServices.logStore.entries;
          final logs = _filterLogs(allLogs);

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1000;
              return ListView(
                padding: EdgeInsets.all(wide ? 28 : 16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '数据源、存储、调度与日志',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, panelConstraints) {
                              final count = panelConstraints.maxWidth >= 1160
                                  ? 4
                                  : panelConstraints.maxWidth >= 650
                                  ? 2
                                  : 1;
                              const gap = 12.0;
                              final panelWidth =
                                  (panelConstraints.maxWidth -
                                      gap * (count - 1)) /
                                  count;
                              return Wrap(
                                spacing: gap,
                                runSpacing: gap,
                                children: [
                                  SizedBox(
                                    width: panelWidth,
                                    child: _buildDataPanel(ds),
                                  ),
                                  SizedBox(
                                    width: panelWidth,
                                    child: _buildStoragePanel(),
                                  ),
                                  SizedBox(
                                    width: panelWidth,
                                    child: _buildPerformancePanel(diag),
                                  ),
                                  SizedBox(
                                    width: panelWidth,
                                    child: _buildIcsPanel(diag),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 22),
                          _buildLogsPanel(allLogs, logs),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDataPanel(Object dataService) {
    return _panel(
      title: AppStrings.of(context, 'diag_section_data'),
      icon: Icons.hub_outlined,
      children: [
        _kv(
          AppStrings.of(context, 'diag_kv_data_service'),
          _typeLabel(dataService),
        ),
        if (dataService is CompositeDataService) ...[
          _kv(
            AppStrings.of(context, 'diag_kv_local'),
            _typeLabel(dataService.local),
          ),
          _kv(
            AppStrings.of(context, 'diag_kv_remote'),
            _typeLabel(dataService.remote),
          ),
        ],
      ],
    );
  }

  Widget _buildStoragePanel() {
    return _panel(
      title: AppStrings.of(context, 'diag_section_storage'),
      icon: Icons.storage_outlined,
      children: [
        FutureBuilder<StorageInfo>(
          future: _storageFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '无法读取本地存储信息。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _refreshStorage,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              );
            }
            final value = snapshot.data;
            if (value == null)
              return Text(AppStrings.of(context, 'common_loading'));
            return Column(
              children: [
                _kv(
                  AppStrings.of(context, 'diag_kv_backend'),
                  _backendLabel(context, value.backend),
                ),
                _kv(
                  AppStrings.of(context, 'diag_kv_exists'),
                  value.exists ? '是' : '否',
                ),
                _kv(
                  AppStrings.of(context, 'diag_kv_bytes'),
                  '${value.bytes} B',
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPerformancePanel(AppDiagnostics diagnostics) {
    return _panel(
      title: AppStrings.of(context, 'diag_section_perf'),
      icon: Icons.speed_outlined,
      children: [
        _kv(
          AppStrings.of(context, 'diag_kv_replan_triggers'),
          diagnostics.replanTriggers.toString(),
        ),
        _kv(
          AppStrings.of(context, 'diag_kv_last_plan_cost_ms'),
          diagnostics.lastSchedulePlanCost?.inMilliseconds.toString() ?? '-',
        ),
        _kv(
          AppStrings.of(context, 'diag_kv_last_plan_at'),
          diagnostics.lastSchedulePlanAt?.toIso8601String() ?? '-',
        ),
        _kv(
          AppStrings.of(context, 'diag_kv_last_plan_reason'),
          diagnostics.lastSchedulePlanReason ?? '-',
        ),
      ],
    );
  }

  Widget _buildIcsPanel(AppDiagnostics diagnostics) {
    return _panel(
      title: AppStrings.of(context, 'diag_section_ics'),
      icon: Icons.sync_alt,
      children: [
        _icsRecord(
          AppStrings.of(context, 'diag_kv_last_export'),
          diagnostics.lastIcsExport,
        ),
        const Divider(height: 18),
        _icsRecord(
          AppStrings.of(context, 'diag_kv_last_import'),
          diagnostics.lastIcsImport,
        ),
      ],
    );
  }

  Widget _buildLogsPanel(List<AppLogEntry> allLogs, List<AppLogEntry> logs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${AppStrings.of(context, 'diag_section_logs')} · ${logs.length}/${allLogs.length}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: AppStrings.of(context, 'diag_tooltip_export_logs'),
              onPressed: _exportLogs,
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: AppStrings.of(context, 'diag_btn_clear'),
              onPressed: () {
                AppServices.logStore.clear();
                AppServices.logStore.info('diagnostics', 'clear logs');
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('diagnostics-log-search'),
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: '筛选日志',
            hintText: '搜索类别、消息或结构化数据',
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          key: const Key('diagnostics-level-filter'),
          spacing: 8,
          runSpacing: 8,
          children: [
            _levelChip('ALL', null),
            _levelChip('DEBUG', AppLogLevel.debug),
            _levelChip('INFO', AppLogLevel.info),
            _levelChip('WARN', AppLogLevel.warn),
            _levelChip('ERROR', AppLogLevel.error),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: logs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    allLogs.isEmpty
                        ? AppStrings.of(context, 'diag_logs_empty')
                        : '没有匹配的日志，请调整筛选条件。',
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < logs.length; i++) ...[
                      _logEntry(logs[i]),
                      if (i < logs.length - 1)
                        Divider(
                          height: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _levelChip(String label, AppLogLevel? level) {
    final selected = _levelFilter == level;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _levelFilter = level),
      showCheckmark: false,
      avatar: level == null
          ? const Icon(Icons.filter_list, size: 16)
          : Icon(Icons.circle, size: 10, color: _levelColor(level)),
    );
  }

  Widget _logEntry(AppLogEntry entry) {
    final color = _levelColor(entry.level);
    final details = <String>[
      entry.at.toLocal().toIso8601String().replaceFirst('T', ' '),
      if (entry.data.isNotEmpty) entry.data.toString(),
      if (entry.error != null) entry.error!,
    ].join(' · ');
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Semantics(
        label: _levelLabel(context, entry.level),
        child: Container(
          width: 48,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            entry.level.name.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      title: Text(
        '${entry.category}: ${entry.message}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _panel({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    ),
  );

  Widget _icsRecord(String label, IcsTransferRecord? record) {
    final colors = Theme.of(context).colorScheme;
    if (record == null) {
      return _kv(label, '-');
    }
    final status = record.ok
        ? AppStrings.of(context, 'common_ok')
        : AppStrings.of(context, 'common_fail');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(
              status,
              style: TextStyle(
                color: record.ok ? colors.tertiary : colors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('${record.count} 条 · ${record.at.toLocal().toIso8601String()}'),
        if (record.path != null)
          Text(
            '路径：${record.path}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (record.error != null)
          Text(
            '错误：${record.error}',
            style: TextStyle(color: colors.error),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}
