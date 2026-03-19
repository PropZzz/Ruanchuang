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

  @override
  void initState() {
    super.initState();
    _discoverServices();
  }

  Future<void> _discoverServices() async {
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
      subtitle: Text('Properties: ${c.properties}'),
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
                    title: const Text('Characteristic Value'),
                    content: Text(value.toString()),
                    actions: [
                      TextButton(
                        child: const Text('OK'),
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
                    title: const Text('Write to Characteristic'),
                    content: TextField(
                      controller: textController,
                      decoration: const InputDecoration(
                        hintText: 'Enter hex value (e.g., 0A, 1F)',
                      ),
                    ),
                    actions: [
                      TextButton(
                        child: const Text('CANCEL'),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      TextButton(
                        child: const Text('WRITE'),
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
                      const SnackBar(content: Text('Write successful')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Write failed: $e')),
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
        title: Text(widget.device.platformName.isNotEmpty ? widget.device.platformName : 'Unknown Device'),
        actions: [
          StreamBuilder<BluetoothConnectionState>(
            stream: widget.device.connectionState,
            initialData: BluetoothConnectionState.connecting,
            builder: (c, snapshot) {
              final state = snapshot.data;
              if (state == BluetoothConnectionState.connected) {
                return TextButton(onPressed: _discoverServices, child: const Text('REFRESH'));
              }
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(state.toString().toUpperCase().split('.')[1]),
              );
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: _services
              .map(
                (s) => Card(
                  child: ExpansionTile(
                    title: Text('Service: ${s.uuid}'),
                    children: s.characteristics.map(_buildCharacteristicTile).toList(),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
