import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:shixuzhipei/services/app_services.dart';

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

  Widget _buildScanResultTile(ScanResult result) {
    return StreamBuilder<BluetoothConnectionState>(
      stream: result.device.connectionState,
      initialData: result.device.isConnected
          ? BluetoothConnectionState.connected
          : BluetoothConnectionState.disconnected,
      builder: (context, snapshot) {
        final state = snapshot.data ?? BluetoothConnectionState.disconnected;

        final trailing = switch (state) {
          BluetoothConnectionState.connecting ||
          BluetoothConnectionState.disconnecting =>
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          BluetoothConnectionState.connected => ElevatedButton(
              onPressed: () async {
                try {
                  await _bluetoothService.disconnect(result.device);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('蓝牙错误：$e')),
                  );
                  return;
                }

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已断开与 ${result.device.platformName} 的连接'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('断开连接'),
            ),
          _ => ElevatedButton(
              onPressed: () async {
                try {
                  await _bluetoothService.connect(result.device);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('蓝牙错误：$e')),
                  );
                  return;
                }

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已连接到 ${result.device.platformName}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
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
