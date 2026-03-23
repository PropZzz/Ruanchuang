import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';

import 'data_service.dart';

class BluetoothService {
  final DataService _dataService;
  final bool _supportsBluetooth = !kIsWeb;
  bool _initialized = false;

  BluetoothService(this._dataService);

  bool get supportsBluetooth => _supportsBluetooth;

  Stream<bool> get isScanning => _supportsBluetooth
      ? FlutterBluePlus.isScanning
      : Stream<bool>.value(false);

  Stream<List<ScanResult>> get scanResults => _supportsBluetooth
      ? FlutterBluePlus.scanResults
      : Stream<List<ScanResult>>.value(const <ScanResult>[]);

  final BehaviorSubject<BluetoothConnectionState> _favoriteDeviceState =
      BehaviorSubject.seeded(BluetoothConnectionState.disconnected);
  Stream<BluetoothConnectionState> get favoriteDeviceState =>
      _favoriteDeviceState.stream;

  String? _favoriteDeviceId;
  StreamSubscription? _faveStateSubscription;
  Timer? _initTimer;

  Future<void> initialize() async {
    if (_initialized || !_supportsBluetooth) return;
    _initialized = true;
    await _init();
  }

  Future<void> _init() async {
    _favoriteDeviceId = await _dataService.getFavoriteDevice();
    if (_favoriteDeviceId == null) return;

    _initTimer?.cancel();
    _initTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final connected = await FlutterBluePlus.connectedDevices;
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
        _initTimer = null;
      }
    });
  }

  void _setFavoriteDevice(BluetoothDevice device) {
    _faveStateSubscription?.cancel();
    _favoriteDeviceId = device.remoteId.toString();
    _favoriteDeviceState.add(
      device.isConnected
          ? BluetoothConnectionState.connected
          : BluetoothConnectionState.disconnected,
    );
    _faveStateSubscription = device.connectionState.listen(
      _favoriteDeviceState.add,
    );
  }

  Future<void> setFavoriteDevice(BluetoothDevice device) async {
    if (!_supportsBluetooth) return;
    await _dataService.setFavoriteDevice(device.remoteId.toString());
    _setFavoriteDevice(device);
  }

  Future<void> startScan({Duration? timeout}) async {
    if (!_supportsBluetooth) return;
    await FlutterBluePlus.startScan(timeout: timeout);
  }

  Future<void> stopScan() async {
    if (!_supportsBluetooth) return;
    await FlutterBluePlus.stopScan();
  }

  Future<void> connect(BluetoothDevice device) async {
    if (!_supportsBluetooth) return;
    await device.connect(license: License.free);
  }

  Future<void> disconnect(BluetoothDevice device) async {
    if (!_supportsBluetooth) return;
    await device.disconnect();
  }

  void dispose() {
    _initTimer?.cancel();
    _initTimer = null;
    _faveStateSubscription?.cancel();
    _faveStateSubscription = null;
    _favoriteDeviceState.close();
  }
}
