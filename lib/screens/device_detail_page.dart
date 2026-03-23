import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/mobile_feedback.dart';

class DeviceDetailPage extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceDetailPage({super.key, required this.device});

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  List<BluetoothService> _services = [];
  final bool _supportsBluetooth = !kIsWeb;

  @override
  void initState() {
    super.initState();
    if (_supportsBluetooth) {
      _discoverServices();
    }
  }

  Future<void> _discoverServices() async {
    if (!_supportsBluetooth) return;
    final services = await widget.device.discoverServices();
    setState(() {
      _services = services;
    });
  }

  Widget _buildCharacteristicTile(BluetoothCharacteristic characteristic) {
    return ListTile(
      title: Text(characteristic.uuid.toString()),
      subtitle: Text('属性: ${characteristic.properties}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (characteristic.properties.read)
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: () async {
                final value = await characteristic.read();
                if (!mounted) return;
                showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('特征值'),
                    content: Text(value.toString()),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (characteristic.properties.write)
            IconButton(
              icon: const Icon(Icons.file_upload),
              onPressed: () async {
                final textController = TextEditingController();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('向特征值写入'),
                    content: TextField(
                      controller: textController,
                      decoration: const InputDecoration(
                        hintText: '请输入十六进制值，例如 0A, 1F',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('写入'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;

                try {
                  final value = textController.text
                      .split(',')
                      .where((item) => item.trim().isNotEmpty)
                      .map((item) => int.parse(item.trim(), radix: 16))
                      .toList();
                  await characteristic.write(value);
                  if (!mounted) return;
                  MobileFeedback.showInfo(
                    context,
                    zhMessage: '写入成功。',
                    enMessage: 'Write completed.',
                  );
                } catch (e, st) {
                  if (!mounted) return;
                  MobileFeedback.showError(
                    context,
                    category: 'bluetooth',
                    message: 'write characteristic failed',
                    zhMessage: '写入失败，请检查输入格式后重试。',
                    enMessage:
                        'Unable to write the value. Please check the input.',
                    error: e,
                    stackTrace: st,
                  );
                }
              },
            ),
          if (characteristic.properties.notify)
            IconButton(
              icon: Icon(
                characteristic.isNotifying
                    ? Icons.notifications_active
                    : Icons.notifications_none,
              ),
              onPressed: () async {
                await characteristic.setNotifyValue(!characteristic.isNotifying);
                if (mounted) {
                  setState(() {});
                }
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.device.platformName.isNotEmpty
              ? widget.device.platformName
              : '未知设备',
        ),
        actions: [
          if (_supportsBluetooth)
            StreamBuilder<BluetoothConnectionState>(
              stream: widget.device.connectionState,
              initialData: BluetoothConnectionState.disconnected,
              builder: (context, snapshot) {
                final state = snapshot.data;
                if (state == BluetoothConnectionState.connected) {
                  return TextButton(
                    onPressed: _discoverServices,
                    child: const Text('刷新'),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(state.toString().toUpperCase().split('.')[1]),
                );
              },
            ),
        ],
      ),
      body: _supportsBluetooth
          ? SingleChildScrollView(
              child: Column(
                children: _services
                    .map(
                      (service) => Card(
                        child: ExpansionTile(
                          title: Text('服务: ${service.uuid}'),
                          children: service.characteristics
                              .map(_buildCharacteristicTile)
                              .toList(),
                        ),
                      ),
                    )
                    .toList(),
              ),
            )
          : Center(
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
                        '当前目标平台不支持蓝牙服务。',
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 4),
                      Text(
                        '请在支持该功能的设备上打开此页面。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
