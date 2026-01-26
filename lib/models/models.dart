import 'package:flutter/material.dart';

/// 日程条目模型
/// 用于日历视图和专注模式的任务展示
class ScheduleEntry {
  /// 任务标题
  final String title;

  /// 任务标签（如：会议、深度工作、碎片时间）
  final String tag;

  /// 在日历视图中的高度（对应时长，通常 80.0 代表 1 小时）
  final double height;

  /// 任务显示的背景色
  final Color color;

  /// 任务开始的具体时间
  final TimeOfDay time;

  const ScheduleEntry({
    required this.title,
    required this.tag,
    required this.height,
    required this.color,
    required this.time,
  });
}

/// 能量状态模型
/// 模拟从智能穿戴设备获取的用户生理状态
class EnergyStatus {
  /// 状态简述 (e.g., '高效 (Flow)')
  final String status;

  /// 详细建议或生理指标描述
  final String description;

  /// 身体电量百分比 (0-100)
  final int batteryPercent;

  const EnergyStatus({
    required this.status,
    required this.description,
    required this.batteryPercent,
  });
}

/// 专注任务模型
/// 用于专注页面的当前任务展示
class Task {
  final String title;
  final String description;

  /// 剩余专注时间（分钟）
  final int remainingMinutes;

  /// 任务进度 (0.0 - 1.0)
  final double progress;

  const Task({
    required this.title,
    required this.description,
    required this.remainingMinutes,
    required this.progress,
  });
}

/// 微任务模型
/// 用于碎片时间管理的短任务
class MicroTask {
  String title;
  String tag;

  /// 预计耗时（分钟）
  int minutes;

  /// 硬件或环境要求（如：需电脑、需电话）
  String? requirement;

  /// 完成状态
  bool done;

  MicroTask({
    required this.title,
    required this.tag,
    required this.minutes,
    this.requirement,
    this.done = false,
  });
}

/// 团队任务模型
/// 用于协作页面的任务列表
class TeamTask {
  String name;
  String role;
  String task;

  /// 任务进度 (0.0 - 1.0)
  double progress;

  /// 该成员是否处于高能状态 (High Energy)
  bool isHighEnergy;

  /// 截止日期
  DateTime? due;

  TeamTask({
    required this.name,
    required this.role,
    required this.task,
    this.progress = 0.0,
    this.isHighEnergy = false,
    this.due,
  });
}

/// 团队成员模型 (API 响应结构)
class TeamMember {
  final String name;
  final String task;
  final double progress;
  final bool isHighEnergy;

  const TeamMember({
    required this.name,
    required this.task,
    required this.progress,
    required this.isHighEnergy,
  });
}

/// 用户画像模型
class UserProfile {
  final String displayName;
  final String status;

  const UserProfile({required this.displayName, required this.status});
}
