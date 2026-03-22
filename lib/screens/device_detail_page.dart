import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
    // Make sure we are connected before discovering services
    // if (widget.device.connectionState != BluetoothConnectionState.connected) {
    //   await widget.device.connect(timeout: const Duration(seconds: 10), license: '');
    // }
    final services = await widget.device.discoverServices();
    setState(() {
      _services = services;
    });
  }

  Widget _buildCharacteristicTile(BluetoothCharacteristic c) {
    return ListTile(
      title: Text(c.uuid.toString()),
      subtitle: Text('属性：${c.properties}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.properties.read)
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: () async {
                final value = await c.read();
                // Show value in a dialog
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('特征值'),
                    content: Text(value.toString()),
                    actions: [
                      TextButton(
                        child: const Text('确定'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (c.properties.write)
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
                        hintText: '请输入十六进制值（例如 0A, 1F）',
                      ),
                    ),
                    actions: [
                      TextButton(
                        child: const Text('取消'),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      TextButton(
                        child: const Text('写入'),
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                );
                if (confirmed ?? false) {
                  try {
                    final value = textController.text
                        .split(',')
                        .map((e) => int.parse(e.trim(), radix: 16))
                        .toList();
                    await c.write(value);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('写入成功')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('写入失败：$e')),
                    );
                  }
                }
              },
            ),
          if (c.properties.notify)
            IconButton(
              icon: Icon(c.isNotifying ? Icons.notifications_active : Icons.notifications_none),
              onPressed: () async {
                await c.setNotifyValue(!c.isNotifying);
                setState(() {});
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
        title: Text(widget.device.platformName.isNotEmpty ? widget.device.platformName : '未知设备'),
        actions: [
          if (_supportsBluetooth)
            StreamBuilder<BluetoothConnectionState>(
              stream: widget.device.connectionState,
              initialData: BluetoothConnectionState.connecting,
              builder: (c, snapshot) {
                final state = snapshot.data;
                if (state == BluetoothConnectionState.connected) {
                  return TextButton(onPressed: _discoverServices, child: const Text('刷新'));
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
                      (s) => Card(
                        child: ExpansionTile(
                          title: Text('服务：${s.uuid}'),
                          children: s.characteristics.map(_buildCharacteristicTile).toList(),
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
