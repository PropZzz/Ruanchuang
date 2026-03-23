import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// 蓝牙管理类
/// 负责蓝牙设备的扫描、连接和管理
class BluetoothManager {
  static final BluetoothManager _instance = BluetoothManager._internal();
  factory BluetoothManager() => _instance;
  BluetoothManager._internal();

  // 蓝牙状态流
  Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;

  // 扫描结果流
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  // 是否正在扫描
  bool get isScanning => FlutterBluePlus.isScanningNow;

  // 已连接设备列表 (Future)
  Future<List<BluetoothDevice>> getConnectedDevices() async {
    return FlutterBluePlus.connectedDevices;
  }

  /// 初始化蓝牙并请求权限
  Future<bool> initialize() async {
    try {
      // 检查平台并请求相应权限
      if (Platform.isAndroid) {
        final bluetoothScan = await Permission.bluetoothScan.request();
        final bluetoothConnect = await Permission.bluetoothConnect.request();
        final location = await Permission.location.request();

        if (bluetoothScan.isDenied || bluetoothConnect.isDenied || location.isDenied) {
          return false;
        }
      } else if (Platform.isIOS) {
        final bluetooth = await Permission.bluetooth.request();
        final location = await Permission.location.request();

        if (bluetooth.isDenied || location.isDenied) {
          return false;
        }
      }

      // 等待蓝牙适配器就绪
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      print('蓝牙初始化失败: $e');
      return false;
    }
  }

  /// 开始扫描蓝牙设备
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
    List<Guid> withServices = const [],
  }) async {
    try {
      // 停止之前的扫描
      await stopScan();

      // 开始新扫描
      await FlutterBluePlus.startScan(
        timeout: timeout,
        withServices: withServices,
      );
    } catch (e) {
      print('开始扫描失败: $e');
      rethrow;
    }
  }

  /// 停止扫描
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      print('停止扫描失败: $e');
    }
  }

  /// 连接到设备
  Future<void> connect(BluetoothDevice device, {
    Duration timeout = const Duration(seconds: 35),
  }) async {
    try {
      await device.connect(license: License.free, timeout: timeout);
      print('成功连接到设备: ${device.remoteId}');
    } catch (e) {
      print('连接设备失败: $e');
      rethrow;
    }
  }

  /// 断开设备连接
  Future<void> disconnect(BluetoothDevice device) async {
    try {
      await device.disconnect();
      print('已断开设备连接: ${device.remoteId}');
    } catch (e) {
      print('断开连接失败: $e');
    }
  }

  /// 发现设备服务和特征
  Future<List<BluetoothService>> discoverServices(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      return services;
    } catch (e) {
      print('发现服务失败: $e');
      return [];
    }
  }

  /// 读取特征值
  Future<List<int>> readCharacteristic(BluetoothCharacteristic characteristic) async {
    try {
      final value = await characteristic.read();
      return value;
    } catch (e) {
      print('读取特征值失败: $e');
      return [];
    }
  }

  /// 写入特征值
  Future<void> writeCharacteristic(
    BluetoothCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) async {
    try {
      await characteristic.write(value, withoutResponse: withoutResponse);
    } catch (e) {
      print('写入特征值失败: $e');
      rethrow;
    }
  }

  /// 监听特征值变化
  Stream<List<int>> onCharacteristicChanged(BluetoothCharacteristic characteristic) {
    return characteristic.onValueReceived;
  }

  /// 设置特征通知
  Future<void> setCharacteristicNotification(
    BluetoothCharacteristic characteristic,
    bool enable,
  ) async {
    try {
      await characteristic.setNotifyValue(enable);
    } catch (e) {
      print('设置通知失败: $e');
      rethrow;
    }
  }

  /// 获取设备连接状态
  Stream<BluetoothConnectionState> connectionState(BluetoothDevice device) {
    return device.connectionState;
  }

  /// 格式化设备名称
  String getDeviceDisplayName(BluetoothDevice device) {
    if (device.platformName.isNotEmpty) {
      return device.platformName;
    }
    return '未知设备 (${device.remoteId})';
  }

  /// 检查设备是否是智能穿戴设备（根据服务UUID）
  bool isWearableDevice(BluetoothDevice device) {
    return true;
  }

  /// 清理资源
  void dispose() {
    stopScan();
  }
}

/// 蓝牙设备信息类
class BluetoothDeviceInfo {
  final BluetoothDevice device;
  final int rssi;
  final AdvertisementData advertisementData;

  BluetoothDeviceInfo({
    required this.device,
    required this.rssi,
    required this.advertisementData,
  });

  String get displayName => device.platformName.isNotEmpty ? device.platformName : '未知设备';
  String get deviceId => device.remoteId.toString();
}