import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:sxzppp/services/app_services.dart';

import 'device_detail_page.dart';


class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  final _bluetoothService = AppServices.bluetoothService;

  Widget _buildScanResultTile(ScanResult result) {
    return StreamBuilder<BluetoothConnectionState>(
      stream: result.device.connectionState,
      initialData: result.device.isConnected
          ? BluetoothConnectionState.connected
          : BluetoothConnectionState.disconnected,
      builder: (c, snapshot) {
        final state = snapshot.data ?? BluetoothConnectionState.disconnected;

        Widget trailing;
        if (state == BluetoothConnectionState.connecting ||
            state == BluetoothConnectionState.disconnecting) {
          trailing = const SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        } else {
          trailing = ElevatedButton(
            child: state == BluetoothConnectionState.connected
                ? const Text('DISCONNECT')
                : const Text('CONNECT'),
            onPressed: () async {
              try {
                if (state == BluetoothConnectionState.connected) {
                  await _bluetoothService.disconnect(result.device);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Disconnected from ${result.device.platformName}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else {
                  await _bluetoothService.connect(result.device);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Connected to ${result.device.platformName}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('蓝牙错误: $e')),
                );
              }
            },
          );
        }

        return ListTile(
          leading: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.bluetooth),
              Text('${result.rssi}'),
            ],
          ),
          title: Text(result.device.platformName.isNotEmpty
              ? result.device.platformName
              : (result.device.advName.isNotEmpty ? result.device.advName : 'Unknown Device')),
          subtitle: Text(result.device.remoteId.toString()),
          trailing: trailing,
          onTap: (state == BluetoothConnectionState.connected)
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
  void dispose() {
    _bluetoothService.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('蓝牙连接'),
        actions: [
          StreamBuilder<bool>(
            stream: _bluetoothService.isScanning,
            initialData: false,
            builder: (c, snapshot) {
              final scanning = snapshot.data ?? false;
              return IconButton(
                icon: Icon(scanning ? Icons.stop : Icons.search),
                onPressed: () {
                  if (scanning) {
                    _bluetoothService.stopScan();
                  } else {
                    _bluetoothService.startScan(timeout: const Duration(seconds: 10));
                  }
                },
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<ScanResult>>(
        stream: _bluetoothService.scanResults,
        initialData: const [],
        builder: (c, snapshot) {
          final results = snapshot.data ?? [];
          if (results.isEmpty) {
            return const Center(child: Text('未发现设备'));
          }
          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final result = results[index];
              return _buildScanResultTile(result);
            },
          );
        },
      ),
    );
  }
}
