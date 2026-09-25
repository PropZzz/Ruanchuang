import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../theme/app_theme.dart';
import '../utils/mobile_feedback.dart';

class DeviceDetailPage extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceDetailPage({super.key, required this.device});

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  List<BluetoothService> _services = [];
  bool _loadingServices = true;
  Object? _serviceError;

  bool get _supportsBluetooth => !kIsWeb;

  @override
  void initState() {
    super.initState();
    if (_supportsBluetooth) {
      _discoverServices();
    }
  }

  Future<void> _discoverServices() async {
    if (!_supportsBluetooth) return;
    setState(() {
      _loadingServices = true;
      _serviceError = null;
    });
    try {
      final services = await widget.device.discoverServices();
      if (!mounted) return;
      setState(() {
        _services = services;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _serviceError = error);
      MobileFeedback.showError(
        context,
        category: 'bluetooth',
        message: 'discover services failed',
        zhMessage: '无法读取设备服务，请确认设备仍保持连接后重试。',
        enMessage:
            'Unable to read device services. Check the connection and retry.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) setState(() => _loadingServices = false);
    }
  }

  Widget _buildCharacteristicTile(BluetoothCharacteristic characteristic) {
    final properties = <String>[
      if (characteristic.properties.read) '可读取',
      if (characteristic.properties.write) '可写入',
      if (characteristic.properties.notify) '可订阅通知',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            characteristic.uuid.toString(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            properties.isEmpty ? '无可用操作' : properties.join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              if (characteristic.properties.read)
                IconButton(
                  tooltip: '读取特征值',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => _readCharacteristic(characteristic),
                ),
              if (characteristic.properties.write)
                IconButton(
                  tooltip: '写入特征值',
                  icon: const Icon(Icons.upload_outlined),
                  onPressed: () => _writeCharacteristic(characteristic),
                ),
              if (characteristic.properties.notify)
                IconButton(
                  tooltip: characteristic.isNotifying ? '停用通知' : '启用通知',
                  icon: Icon(
                    characteristic.isNotifying
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_outlined,
                  ),
                  onPressed: () => _toggleNotifications(characteristic),
                ),
            ],
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Future<void> _readCharacteristic(
    BluetoothCharacteristic characteristic,
  ) async {
    try {
      final value = await characteristic.read();
      if (!mounted) return;
      final hex = value
          .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      await _showAdaptivePrompt<void>(
        (context, isSheet) => _promptSurface(
          context,
          isSheet: isSheet,
          title: '特征值',
          content: SelectableText(hex.isEmpty ? '（空）' : hex),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'bluetooth',
        message: 'read characteristic failed',
        zhMessage: '读取特征值失败，请确认设备连接后重试。',
        enMessage:
            'Unable to read the characteristic. Check the connection and retry.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _writeCharacteristic(
    BluetoothCharacteristic characteristic,
  ) async {
    final value = await _promptForBytes();
    if (value == null) return;
    try {
      await characteristic.write(value);
      if (!mounted) return;
      MobileFeedback.showInfo(
        context,
        zhMessage: '写入成功。',
        enMessage: 'Write completed.',
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'bluetooth',
        message: 'write characteristic failed',
        zhMessage: '写入失败，请确认设备连接后重试。',
        enMessage: 'Unable to write the value. Check the connection and retry.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _toggleNotifications(
    BluetoothCharacteristic characteristic,
  ) async {
    try {
      await characteristic.setNotifyValue(!characteristic.isNotifying);
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'bluetooth',
        message: 'notification setup failed',
        zhMessage: '通知设置失败，请确认设备连接后重试。',
        enMessage:
            'Unable to update notifications. Check the connection and retry.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<int>?> _promptForBytes() async {
    final controller = TextEditingController();
    String? inputError;
    try {
      return await _showAdaptivePrompt<List<int>>(
        (context, isSheet) => StatefulBuilder(
          builder: (context, setDialogState) => _promptSurface(
            context,
            isSheet: isSheet,
            title: '写入十六进制值',
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '特征值',
                hintText: '0A, 1F',
                helperText: '每个字节为 00 至 FF，可用空格或逗号分隔。',
                errorText: inputError,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final value = _parseHexBytes(controller.text);
                  if (value == null) {
                    setDialogState(
                      () => inputError = '请输入有效的十六进制字节，例如 0A, 1F。',
                    );
                    return;
                  }
                  Navigator.of(context).pop(value);
                },
                child: const Text('写入'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<T?> _showAdaptivePrompt<T>(
    Widget Function(BuildContext context, bool isSheet) builder,
  ) {
    if (MediaQuery.sizeOf(context).width < AppTheme.compactShellBreakpoint) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: builder(context, true),
        ),
      );
    }
    return showDialog<T>(
      context: context,
      builder: (context) => builder(context, false),
    );
  }

  Widget _promptSurface(
    BuildContext context, {
    required bool isSheet,
    required String title,
    required Widget content,
    required List<Widget> actions,
  }) {
    if (!isSheet) {
      return AlertDialog(
        title: Text(title),
        content: content,
        actions: actions,
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              content,
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, children: actions),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.device.platformName.isNotEmpty
        ? widget.device.platformName
        : '未知设备';
    return Scaffold(
      backgroundColor: AppWindowTones.canvas(context, AppWindowTone.neutral),
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (_supportsBluetooth)
            StreamBuilder<BluetoothConnectionState>(
              stream: widget.device.connectionState,
              initialData: BluetoothConnectionState.disconnected,
              builder: (context, snapshot) {
                final state =
                    snapshot.data ?? BluetoothConnectionState.disconnected;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ConnectionStateLabel(state: state),
                      if (state == BluetoothConnectionState.connected)
                        IconButton(
                          tooltip: '刷新服务',
                          onPressed: _loadingServices
                              ? null
                              : _discoverServices,
                          icon: const Icon(Icons.refresh),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: _supportsBluetooth
          ? LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final overview = _buildDeviceOverview(name);
                final services = _buildServicesPanel();
                return SingleChildScrollView(
                  padding: EdgeInsets.all(wide ? 28 : 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 320, child: overview),
                                const SizedBox(width: 18),
                                Expanded(child: services),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                overview,
                                const SizedBox(height: 14),
                                services,
                              ],
                            ),
                    ),
                  ),
                );
              },
            )
          : Center(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bluetooth_disabled,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      SizedBox(height: 8),
                      Text('当前目标平台不支持蓝牙服务。', textAlign: TextAlign.center),
                      SizedBox(height: 4),
                      Text(
                        '请在支持该功能的设备上打开此页面。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildDeviceOverview(String name) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bluetooth_connected,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('远端 ID', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            SelectableText(widget.device.remoteId.toString()),
            const SizedBox(height: 14),
            StreamBuilder<BluetoothConnectionState>(
              stream: widget.device.connectionState,
              initialData: BluetoothConnectionState.disconnected,
              builder: (context, snapshot) => _ConnectionStateLabel(
                state: snapshot.data ?? BluetoothConnectionState.disconnected,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServicesPanel() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '设备服务',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '刷新服务',
                  onPressed: _loadingServices ? null : _discoverServices,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (_loadingServices)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_serviceError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('无法读取设备服务。'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _discoverServices,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            )
          else if (_services.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
              child: Row(
                children: [
                  Icon(
                    Icons.layers_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('尚无可用服务。')),
                ],
              ),
            )
          else
            ..._services.map(
              (service) => ExpansionTile(
                leading: const Icon(Icons.hub_outlined),
                title: const Text('服务'),
                subtitle: SelectableText(service.uuid.toString()),
                children: service.characteristics.isEmpty
                    ? const [
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('此服务没有可用特征值。'),
                        ),
                      ]
                    : service.characteristics
                          .map(_buildCharacteristicTile)
                          .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConnectionStateLabel extends StatelessWidget {
  const _ConnectionStateLabel({required this.state});

  final BluetoothConnectionState state;

  @override
  Widget build(BuildContext context) {
    final connected = state == BluetoothConnectionState.connected;
    final scheme = Theme.of(context).colorScheme;
    final color = connected ? scheme.tertiary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(connected ? Icons.link : Icons.link_off, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            connected ? '已连接' : '未连接',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

List<int>? _parseHexBytes(String text) {
  final parts = text
      .trim()
      .split(RegExp(r'[\s,]+'))
      .where((part) => part.isNotEmpty);
  if (parts.isEmpty) return null;
  final bytes = <int>[];
  for (final part in parts) {
    final normalized = part.toLowerCase().startsWith('0x')
        ? part.substring(2)
        : part;
    if (!RegExp(r'^[0-9a-fA-F]{1,2}$').hasMatch(normalized)) return null;
    bytes.add(int.parse(normalized, radix: 16));
  }
  return bytes;
}
