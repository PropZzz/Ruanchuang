import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:shixuzhipei/services/app_services.dart';
import '../theme/app_theme.dart';

import '../utils/mobile_feedback.dart';
import 'device_detail_page.dart';
import 'main_screen.dart';

class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  final _bluetoothService = AppServices.bluetoothService;

  bool get _supportsBluetooth => _bluetoothService.supportsBluetooth;

  @override
  void dispose() {
    if (_supportsBluetooth) {
      _bluetoothService.stopScan();
    }
    super.dispose();
  }

  Widget _buildUnsupportedState(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bluetooth_disabled,
                  size: 42,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  '当前平台不可用蓝牙。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '请在支持真实硬件的设备版本上使用。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleScan(bool scanning) async {
    try {
      if (scanning) {
        await _bluetoothService.stopScan();
      } else {
        await _bluetoothService.startScan(timeout: const Duration(seconds: 10));
      }
    } catch (e, st) {
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'bluetooth',
        message: 'scan failed',
        zhMessage: '无法启动蓝牙扫描，请检查系统权限后重试。',
        enMessage: 'Bluetooth scan failed. Check system permissions and retry.',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _handleDisconnect(BluetoothDevice device) async {
    try {
      await _bluetoothService.disconnect(device);
      if (!mounted) return;
      MobileFeedback.showInfo(
        context,
        zhMessage: '设备已断开连接。',
        enMessage: 'Device disconnected.',
      );
    } catch (e, st) {
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'bluetooth',
        message: 'disconnect failed',
        zhMessage: '暂时无法断开设备连接。',
        enMessage: 'Unable to disconnect from the device.',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _handleConnect(BluetoothDevice device) async {
    try {
      await _bluetoothService.connect(device);
      if (!mounted) return;
      MobileFeedback.showInfo(
        context,
        zhMessage: '设备已连接。',
        enMessage: 'Device connected.',
      );
    } catch (e, st) {
      if (!mounted) return;
      MobileFeedback.showError(
        context,
        category: 'bluetooth',
        message: 'connect failed',
        zhMessage: '暂时无法连接设备。',
        enMessage: 'Unable to connect to the device.',
        error: e,
        stackTrace: st,
      );
    }
  }

  Widget _buildScanResultTile(ScanResult result) {
    return StreamBuilder<BluetoothConnectionState>(
      stream: result.device.connectionState,
      initialData: result.device.isConnected
          ? BluetoothConnectionState.connected
          : BluetoothConnectionState.disconnected,
      builder: (context, snapshot) {
        final state = snapshot.data ?? BluetoothConnectionState.disconnected;
        final connected = state == BluetoothConnectionState.connected;
        final colors = Theme.of(context).colorScheme;
        final deviceName = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : result.device.advName.isNotEmpty
            ? result.device.advName
            : '未知设备';

        return LayoutBuilder(
          builder: (context, constraints) {
            final info = Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.bluetooth, color: colors.secondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      SelectableText(
                        result.device.remoteId.toString(),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _ConnectionStatus(connected: connected),
              ],
            );
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'RSSI ${result.rssi} dBm',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(width: 8),
                connected
                    ? OutlinedButton(
                        onPressed: () => _handleDisconnect(result.device),
                        child: const Text('断开连接'),
                      )
                    : FilledButton(
                        onPressed: () => _handleConnect(result.device),
                        child: const Text('连接'),
                      ),
                if (connected)
                  IconButton(
                    tooltip: '查看设备详情',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MainScreen(
                          secondaryPage: DeviceDetailPage(
                            device: result.device,
                          ),
                          secondaryTabIndex: 4,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
              ],
            );

            return Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                onTap: connected
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MainScreen(
                            secondaryPage: DeviceDetailPage(
                              device: result.device,
                            ),
                            secondaryTabIndex: 4,
                          ),
                        ),
                      )
                    : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: constraints.maxWidth >= 640
                      ? Row(
                          children: [
                            Expanded(child: info),
                            const SizedBox(width: 12),
                            actions,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            info,
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.centerRight,
                              child: actions,
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppWindowTones.canvas(context, AppWindowTone.neutral),
      appBar: AppBar(
        title: const Text('蓝牙外设'),
        actions: [
          if (_supportsBluetooth)
            StreamBuilder<bool>(
              stream: _bluetoothService.isScanning,
              initialData: false,
              builder: (context, snapshot) {
                final scanning = snapshot.data ?? false;
                return IconButton(
                  tooltip: scanning ? '停止扫描' : '开始扫描',
                  onPressed: () => _toggleScan(scanning),
                  icon: Icon(scanning ? Icons.stop : Icons.bluetooth_searching),
                );
              },
            )
          else
            const IconButton(
              tooltip: '当前平台不支持蓝牙',
              icon: Icon(Icons.bluetooth_disabled),
              onPressed: null,
            ),
        ],
      ),
      body: _supportsBluetooth
          ? StreamBuilder<bool>(
              stream: _bluetoothService.isScanning,
              initialData: false,
              builder: (context, scanSnapshot) {
                final scanning = scanSnapshot.data ?? false;
                return StreamBuilder<List<ScanResult>>(
                  stream: _bluetoothService.scanResults,
                  initialData: const <ScanResult>[],
                  builder: (context, snapshot) {
                    final results = snapshot.data ?? const <ScanResult>[];
                    final wide = MediaQuery.sizeOf(context).width >= 960;
                    return ListView(
                      padding: EdgeInsets.all(wide ? 28 : 16),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Row(
                                      children: [
                                        Icon(
                                          scanning
                                              ? Icons.bluetooth_searching
                                              : Icons.bluetooth,
                                          color: scanning
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.secondary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            scanning
                                                ? '正在搜索附近设备'
                                                : '管理附近的蓝牙设备与传感器',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                        ),
                                        _ConnectionStatus(
                                          connected: false,
                                          label: scanning ? '扫描中' : '就绪',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '周边 BLE 设备',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                    ),
                                    Text(
                                      '${results.length} 个设备',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (results.isEmpty)
                                  _buildEmptyResults(scanning)
                                else
                                  ...results.map(
                                    (result) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: _buildScanResultTile(result),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            )
          : _buildUnsupportedState(context),
    );
  }

  Widget _buildEmptyResults(bool scanning) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
        child: Column(
          children: [
            Icon(
              scanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
              size: 34,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('未找到设备。', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(
              scanning ? '保持设备在附近并处于可发现状态。' : '请确认设备已开启，然后重新扫描。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (!scanning) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _toggleScan(false),
                icon: const Icon(Icons.refresh),
                label: const Text('重新扫描'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({required this.connected, this.label});

  final bool connected;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = connected ? scheme.tertiary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
            label ?? (connected ? '已连接' : '未连接'),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
