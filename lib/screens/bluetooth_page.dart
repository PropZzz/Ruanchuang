import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:shixuzhipei/services/app_services.dart';

import '../utils/mobile_feedback.dart';
import 'device_detail_page.dart';

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
    return Center(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.bluetooth_disabled, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                '当前平台不可用蓝牙。',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 4),
              Text(
                '请在支持真实硬件的设备版本上使用。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
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

        final trailing = switch (state) {
          BluetoothConnectionState.connected => ElevatedButton(
              onPressed: () => _handleDisconnect(result.device),
              child: const Text('断开连接'),
            ),
          _ => ElevatedButton(
              onPressed: () => _handleConnect(result.device),
              child: const Text('连接'),
            ),
        };

        return ListTile(
          leading: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bluetooth),
              Text('${result.rssi}'),
            ],
          ),
          title: Text(
            result.device.platformName.isNotEmpty
                ? result.device.platformName
                : (result.device.advName.isNotEmpty
                    ? result.device.advName
                    : '未知设备'),
          ),
          subtitle: Text(result.device.remoteId.toString()),
          trailing: trailing,
          onTap: state == BluetoothConnectionState.connected
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DeviceDetailPage(device: result.device),
                    ),
                  )
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('蓝牙'),
        actions: [
          if (_supportsBluetooth)
            StreamBuilder<bool>(
              stream: _bluetoothService.isScanning,
              initialData: false,
              builder: (context, snapshot) {
                final scanning = snapshot.data ?? false;
                return IconButton(
                  icon: Icon(scanning ? Icons.stop : Icons.search),
                  onPressed: () {
                    if (scanning) {
                      _bluetoothService.stopScan();
                    } else {
                      _bluetoothService.startScan(
                        timeout: const Duration(seconds: 10),
                      );
                    }
                  },
                );
              },
            )
          else
            const IconButton(
              icon: Icon(Icons.block),
              onPressed: null,
            ),
        ],
      ),
      body: _supportsBluetooth
          ? StreamBuilder<List<ScanResult>>(
              stream: _bluetoothService.scanResults,
              initialData: const <ScanResult>[],
              builder: (context, snapshot) {
                final results = snapshot.data ?? const <ScanResult>[];
                if (results.isEmpty) {
                  return const Center(child: Text('未找到设备。'));
                }
                return ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    return _buildScanResultTile(results[index]);
                  },
                );
              },
            )
          : _buildUnsupportedState(context),
    );
  }
}
