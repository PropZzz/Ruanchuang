import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import 'data_service.dart';

/// 模拟数据服务实现
/// 使用内存列表存储数据，模拟网络延迟
class MockDataService implements DataService {
  // 私有构造函数，防止外部实例化
  MockDataService._private();

  // 单例实例
  static final MockDataService instance = MockDataService._private();

  // 内存中的模拟数据源
  final List<ScheduleEntry> _scheduleData = [
    ScheduleEntry(
      title: "深度工作：架构设计",
      tag: "状态匹配：完美",
      height: 120,
      color: Colors.teal,
      time: const TimeOfDay(hour: 9, minute: 0),
    ), // 90 mins
    ScheduleEntry(
      title: "产品评审会",
      tag: "协作窗口",
      height: 80,
      color: Colors.blue,
      time: const TimeOfDay(hour: 14, minute: 0),
    ), // 60 mins
    ScheduleEntry(
      title: "处理邮件 (微任务)",
      tag: "利用碎片时间",
      height: 40,
      color: Colors.orange,
      time: const TimeOfDay(hour: 11, minute: 30),
    ), // 30 mins
    ScheduleEntry(
      title: "项目周报撰写",
      tag: "常规任务",
      height: 60,
      color: Colors.blueAccent,
      time: const TimeOfDay(hour: 16, minute: 0),
    ), // 45 mins
  ];

  // --- 接口实现 ---

  @override
  Future<EnergyStatus> getEnergyStatus() async {
    // 模拟网络延迟 120ms
    await Future.delayed(const Duration(milliseconds: 120));
    return EnergyStatus(
      status: '高效 (Flow)',
      description: 'HRV 稳定，适合深度思考',
      batteryPercent: 85,
    );
  }

  @override
  Future<Task> getCurrentTask() async {
    await Future.delayed(const Duration(milliseconds: 120));
    return Task(
      title: '编写时序优化算法核心模块',
      description: '实现任务调度与能量感知',
      remainingMinutes: 45,
      progress: 0.3,
    );
  }

  @override
  Future<List<Task>> getNextTasks() async {
    await Future.delayed(const Duration(milliseconds: 80));
    return [
      Task(
        title: '团队进度同步会',
        description: '15:00 视频会议',
        remainingMinutes: 0,
        progress: 0,
      ),
      Task(
        title: '整理开发文档 (微任务)',
        description: '16:30 文档整理',
        remainingMinutes: 0,
        progress: 0,
      ),
    ];
  }

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() async {
    await Future.delayed(const Duration(milliseconds: 50));
    // 返回按时间排序的副本，防止外部直接修改源数据
    _scheduleData.sort((a, b) {
      final aMinutes = a.time.hour * 60 + a.time.minute;
      final bMinutes = b.time.hour * 60 + b.time.minute;
      return aMinutes.compareTo(bMinutes);
    });
    return List<ScheduleEntry>.from(_scheduleData);
  }

  @override
  Future<void> addScheduleEntry(ScheduleEntry entry) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _scheduleData.add(entry);
  }

  @override
  Future<void> removeScheduleEntry(ScheduleEntry entry) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _scheduleData.removeWhere(
      (e) => e.title == entry.title && e.time == entry.time,
    );
  }

  @override
  Future<List<MicroTask>> getMicroTasks() async {
    await Future.delayed(const Duration(milliseconds: 60));
    return [
      MicroTask(title: '回复 HR 邮件', tag: '需电脑', minutes: 5, requirement: '电脑'),
      MicroTask(title: '电话确认需求', tag: '移动场景', minutes: 10, requirement: '电话'),
      MicroTask(title: '整理桌面文件', tag: '低脑力', minutes: 15, requirement: '桌面'),
      MicroTask(title: '查看行业新闻', tag: '任意', minutes: 8, requirement: '任意'),
    ];
  }

  @override
  Future<List<TeamMember>> getTeamMembers() async {
    await Future.delayed(const Duration(milliseconds: 80));
    return [
      const TeamMember(
        name: '李一诺 (PM)',
        task: '0.5.1 文档修订',
        progress: 0.9,
        isHighEnergy: true,
      ),
      const TeamMember(
        name: '宋子谦 (Dev)',
        task: 'Transformer 模型调试',
        progress: 0.6,
        isHighEnergy: true,
      ),
      const TeamMember(
        name: '杨子翔 (Dev)',
        task: '后端 API 联调',
        progress: 0.4,
        isHighEnergy: false,
      ),
    ];
  }

  @override
  Future<UserProfile> getUserProfile() async {
    await Future.delayed(const Duration(milliseconds: 60));
    return const UserProfile(displayName: 'BattleMan User', status: '已连接设备');
  }
}
