import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';

import 'data_service.dart';

class BluetoothService {
  final DataService _dataService;

  BluetoothService(this._dataService) {
    _init();
  }

  Stream<bool> get isScanning => FlutterBluePlus.isScanning;
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  final BehaviorSubject<BluetoothConnectionState> _favoriteDeviceState =
      BehaviorSubject.seeded(BluetoothConnectionState.disconnected);
  Stream<BluetoothConnectionState> get favoriteDeviceState =>
      _favoriteDeviceState.stream;

  String? _favoriteDeviceId;
  StreamSubscription? _faveStateSubscription;

  void _init() async {
    _favoriteDeviceId = await _dataService.getFavoriteDevice();
    if (_favoriteDeviceId == null) return;

    // Periodically check connected devices
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      final connected = FlutterBluePlus.connectedDevices;
      BluetoothDevice? fave;
      for (final d in connected) {
        if (d.remoteId.toString() == _favoriteDeviceId) {
          fave = d;
          break;
        }
      }
      if (fave != null) {
        _setFavoriteDevice(fave);
        timer.cancel();
      }
    });
  }


  void _setFavoriteDevice(BluetoothDevice device) {
    _faveStateSubscription?.cancel();
    _favoriteDeviceId = device.remoteId.toString();
    _favoriteDeviceState
        .add(device.isConnected ? BluetoothConnectionState.connected : BluetoothConnectionState.disconnected);
    _faveStateSubscription = device.connectionState.listen(_favoriteDeviceState.add);
  }

  Future<void> setFavoriteDevice(BluetoothDevice device) async {
    await _dataService.setFavoriteDevice(device.remoteId.toString());
    _setFavoriteDevice(device);
  }

  Future<void> startScan({Duration? timeout}) async {
    await FlutterBluePlus.startScan(timeout: timeout);
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Future<void> connect(BluetoothDevice device) async {
    await device.connect(license: License.free);
  }

  Future<void> disconnect(BluetoothDevice device) async {
    await device.disconnect();
  }
}

