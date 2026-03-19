import 'package:flutter/material.dart';
import '../models/models.dart';

/// 团队调度算法工具类
class TeamScheduler {
  /// 工作时间范围：8:00-20:00
  static const TimeOfDay workStart = TimeOfDay(hour: 8, minute: 0);
  static const TimeOfDay workEnd = TimeOfDay(hour: 20, minute: 0);

  /// 计算团队成员的最大空闲时间段
  /// 返回最长的连续空闲时间段，如果没有找到则返回null
  static TimeRange? findMaxFreeTimeSlot(List<TeamMember> members) {
    if (members.isEmpty) return null;

    // 将工作时间离散化为15分钟间隔
    const int intervalMinutes = 15;
    final List<TimeOfDay> timeSlots = _generateTimeSlots(intervalMinutes);

    // 为每个时间段检查是否有成员忙碌
    final List<bool> isBusy = List.filled(timeSlots.length, false);

    for (final member in members) {
      for (int i = 0; i < timeSlots.length; i++) {
        final time = timeSlots[i];
        // 检查这个时间点是否有成员忙碌
        for (final busyTime in member.busyTimes) {
          if (busyTime.contains(time)) {
            isBusy[i] = true;
            break;
          }
        }
      }
    }

    // 找到最长的连续空闲时间段
    return _findLongestFreeSlot(timeSlots, isBusy, intervalMinutes);
  }

  /// 生成时间段列表（15分钟间隔）
  static List<TimeOfDay> _generateTimeSlots(int intervalMinutes) {
    final List<TimeOfDay> slots = [];
    final startMinutes = workStart.hour * 60 + workStart.minute;
    final endMinutes = workEnd.hour * 60 + workEnd.minute;

    for (int minutes = startMinutes; minutes <= endMinutes; minutes += intervalMinutes) {
      final hour = minutes ~/ 60;
      final minute = minutes % 60;
      slots.add(TimeOfDay(hour: hour, minute: minute));
    }

    return slots;
  }

  /// 找到最长的连续空闲时间段
  static TimeRange? _findLongestFreeSlot(
    List<TimeOfDay> timeSlots,
    List<bool> isBusy,
    int intervalMinutes,
  ) {
    if (timeSlots.isEmpty) return null;

    int maxLength = 0;
    int currentLength = 0;
    int startIndex = -1;
    int maxStartIndex = -1;

    for (int i = 0; i < isBusy.length; i++) {
      if (!isBusy[i]) {
        if (currentLength == 0) {
          startIndex = i;
        }
        currentLength++;
      } else {
        if (currentLength > maxLength) {
          maxLength = currentLength;
          maxStartIndex = startIndex;
        }
        currentLength = 0;
        startIndex = -1;
      }
    }

    // 检查最后一个连续段
    if (currentLength > maxLength) {
      maxLength = currentLength;
      maxStartIndex = startIndex;
    }

    if (maxStartIndex == -1 || maxLength < 2) {
      // 至少需要30分钟（2个15分钟间隔）的空闲时间
      return null;
    }

    final startTime = timeSlots[maxStartIndex];
    final endIndex = maxStartIndex + maxLength - 1;
    final endTime = timeSlots[endIndex];

    return TimeRange(start: startTime, end: endTime);
  }

  /// 格式化时间段为可读字符串
  static String formatTimeRange(TimeRange? timeRange, BuildContext context) {
    if (timeRange == null) {
      return '暂无合适时间';
    }

    final startStr = _formatTimeOfDay(timeRange.start);
    final endStr = _formatTimeOfDay(timeRange.end);
    final duration = timeRange.durationMinutes;

    if (duration >= 60) {
      final hours = duration ~/ 60;
      final minutes = duration % 60;
      final durationStr = minutes > 0 ? '${hours}小时${minutes}分钟' : '${hours}小时';
      return '$startStr - $endStr ($durationStr)';
    } else {
      return '$startStr - $endStr (${duration}分钟)';
    }
  }

  /// 格式化TimeOfDay为字符串
  static String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// 获取建议的会议时间列表（前3个最长空闲时间段）
  static List<TimeRange> findTopFreeTimeSlots(List<TeamMember> members, {int topN = 3}) {
    if (members.isEmpty) return [];

    const int intervalMinutes = 15;
    final List<TimeOfDay> timeSlots = _generateTimeSlots(intervalMinutes);
    final List<bool> isBusy = List.filled(timeSlots.length, false);

    // 标记忙碌时间
    for (final member in members) {
      for (int i = 0; i < timeSlots.length; i++) {
        final time = timeSlots[i];
        for (final busyTime in member.busyTimes) {
          if (busyTime.contains(time)) {
            isBusy[i] = true;
            break;
          }
        }
      }
    }

    // 找到所有空闲时间段
    final List<TimeRange> freeSlots = _findAllFreeSlots(timeSlots, isBusy, intervalMinutes);

    // 按时长排序，返回前topN个
    freeSlots.sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes));
    return freeSlots.take(topN).toList();
  }

  /// 找到所有空闲时间段
  static List<TimeRange> _findAllFreeSlots(
    List<TimeOfDay> timeSlots,
    List<bool> isBusy,
    int intervalMinutes,
  ) {
    final List<TimeRange> freeSlots = [];

    int currentLength = 0;
    int startIndex = -1;

    for (int i = 0; i < isBusy.length; i++) {
      if (!isBusy[i]) {
        if (currentLength == 0) {
          startIndex = i;
        }
        currentLength++;
      } else {
        if (currentLength >= 2) { // 至少30分钟
          final startTime = timeSlots[startIndex];
          final endIndex = startIndex + currentLength - 1;
          final endTime = timeSlots[endIndex];
          freeSlots.add(TimeRange(start: startTime, end: endTime));
        }
        currentLength = 0;
        startIndex = -1;
      }
    }

    // 检查最后一个连续段
    if (currentLength >= 2) {
      final startTime = timeSlots[startIndex];
      final endIndex = startIndex + currentLength - 1;
      final endTime = timeSlots[endIndex];
      freeSlots.add(TimeRange(start: startTime, end: endTime));
    }

    return freeSlots;
  }
}