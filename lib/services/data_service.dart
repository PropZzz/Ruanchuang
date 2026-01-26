import '../models/models.dart';

/// 数据服务接口
/// 定义了 App 所需的所有数据获取能力
abstract class DataService {
  /// 获取当前用户的能量/生理状态
  Future<EnergyStatus> getEnergyStatus();

  /// 获取当前正在进行的专注任务
  Future<Task> getCurrentTask();

  /// 获取后续待办任务列表
  Future<List<Task>> getNextTasks();

  /// 获取完整的日程安排
  Future<List<ScheduleEntry>> getScheduleEntries();

  /// 添加新的日程
  Future<void> addScheduleEntry(ScheduleEntry entry);

  /// 移除指定日程
  Future<void> removeScheduleEntry(ScheduleEntry entry);

  /// 获取微任务池
  Future<List<MicroTask>> getMicroTasks();

  /// 获取团队成员状态
  Future<List<TeamMember>> getTeamMembers();

  /// 获取用户基础信息
  Future<UserProfile> getUserProfile();
}
