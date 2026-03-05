import 'package:flutter/material.dart';

class AppStrings {
  static const Map<String, Map<String, String>> _data = {
    'zh': {
      // 底部导航
      'nav_focus': '专注',
      'nav_schedule': '日程',
      'nav_micro': '微任务',
      'nav_team': '团队',
      'nav_profile': '我的',

      // 通用按钮
      'btn_add': '添加',
      'btn_cancel': '取消',
      'btn_confirm': '确认',
      'btn_delete': '删除',
      'btn_save': '保存',
      'btn_start': '开始',
      'btn_pause': '暂停',
      'btn_finish': '完成',
      'btn_completed': '已完成',
      'btn_incomplete': '未完成',

      // 通用标签
      'label_title': '标题',
      'label_tag': '标签',
      'label_desc': '描述（可选）',

      // Dialog 标题 (修复此处 key)
      'dialog_add_title': '新增日程',
      'dialog_del_title': '删除日程',
      'dialog_del_content': '确认删除',

      // 专注页 (Focus Page) - 标题移除英文
      'focus_title': '当下专注',
      'focus_status_label': '当前状态：',
      // 新增状态文案
      'status_flow_value': '高效 (Flow)',
      'status_flow_desc': 'HRV 稳定，适合深度思考',

      'focus_header_current': '当前任务',
      'focus_header_next': '后续待办',
      'focus_empty_task': '今日已无更多日程',
      'focus_time_remaining': '剩余时间: ',
      'focus_snack_start': '将在 {min} 分钟后开始 {task}',
      'focus_snack_upcoming': '{task} 将在 {min} 分钟后开始...',

      // 微任务页 (Micro Task Page) - 标题移除英文
      'micro_title': '微任务晶体池',
      'micro_ai_suggestion': 'AI 识别到您现在有 15 分钟碎片时间，建议立即处理以下任务：',
      'micro_btn_fill': '一键填充',
      'micro_btn_add': '添加微任务',
      'micro_dialog_add': '新增微任务',
      'micro_dialog_del': '删除微任务',
      'micro_label_min': '预计分钟:',
      'micro_card_min': '分钟',

      // 团队页 (Team Page) - 标题移除英文
      'team_title': '团队协作',
      'team_rec_title': '协作黄金窗口推荐',
      'team_best_time': '最佳会议时间：今天 15:00 - 16:00',
      'team_btn_book': '发起预约',
      'team_reason': '理由：全员处于「平稳期」且无核心任务冲突',
      'team_track_title': '项目进度追踪 (开发组)',
      'team_btn_add_task': '添加任务',
      'team_dialog_add': '添加团队任务',
      'team_label_name': '成员姓名',
      'team_label_role': '角色',
      'team_label_task': '任务标题',
      'team_label_progress': '进度',
      'team_label_high_energy': '高效状态:',
      'team_label_due': '到期时间:',
      'team_card_ongoing': '正在进行:',
      'team_card_due': '到期:',

      // 日程页 (Calendar Page) - 标题移除英文
      'calendar_title': '智能日程',
      'label_duration': '时长(分钟):',
      'label_start_time': '开始时间:',
      'color_green': '绿色',
      'color_blue': '蓝色',
      'color_orange': '橙色',

      // 个人中心 (Profile Page) - 标题移除英文
      'profile_title': '效率画像',
      'profile_device': '设备连接 (Apple Watch/Huawei)',
      'profile_connected': '已连接',
      'profile_auth': '第三方应用授权 (MCP)',
      'settings_title': '系统设置',
      'settings_language': '更改语言',
      'settings_notify': '通知管理',
      'settings_dark': '深色模式',
      'lang_zh': '🇨🇳 中文 (简体)',
      'lang_en': '🇺🇸 English',
    },
    'en': {
      // Nav
      'nav_focus': 'Focus',
      'nav_schedule': 'Schedule',
      'nav_micro': 'MicroTask',
      'nav_team': 'Team',
      'nav_profile': 'My Profile',

      // Common Buttons
      'btn_add': 'Add',
      'btn_cancel': 'Cancel',
      'btn_confirm': 'Confirm',
      'btn_delete': 'Delete',
      'btn_save': 'Save',
      'btn_start': 'Start',
      'btn_pause': 'Pause',
      'btn_finish': 'Complete',
      'btn_completed': 'Completed',
      'btn_incomplete': 'Incomplete',

      // Common Labels
      'label_title': 'Title',
      'label_tag': 'Tag',
      'label_desc': 'Description (Optional)',

      // Dialogs
      'dialog_add_title': 'New Schedule',
      'dialog_del_title': 'Delete Schedule',
      'dialog_del_content': 'Delete',

      // Focus Page
      'focus_title': 'Focus Now',
      'focus_status_label': 'Status:',
      // Status Localized
      'status_flow_value': 'Flow State',
      'status_flow_desc': 'HRV Stable, ready for deep work',

      'focus_header_current': 'CURRENT TASK',
      'focus_header_next': 'Upcoming Tasks',
      'focus_empty_task': 'No more schedules for today',
      'focus_time_remaining': 'Time Left: ',
      'focus_snack_start': 'Starting {task} in {min} min',
      'focus_snack_upcoming': '{task} will start in {min} min...',

      // Micro Task Page
      'micro_title': 'Micro Task Crystal Pool',
      'micro_ai_suggestion':
          'AI detected you have 15 minutes of fragmented time now. Suggested tasks:',
      'micro_btn_fill': 'One-Click Fill',
      'micro_btn_add': 'Add Micro Task',
      'micro_dialog_add': 'Add New Micro Task',
      'micro_dialog_del': 'Delete Micro Task',
      'micro_label_min': 'Est. Minutes:',
      'micro_card_min': 'mins',

      // Team Page
      'team_title': 'Team Collaboration',
      'team_rec_title': 'Recommended Golden Collaboration Window',
      'team_best_time': 'Best Time: Today 15:00 - 16:00',
      'team_btn_book': 'Initiate Reservation',
      'team_reason':
          'Reason: All members are in a "stable period" with no core task conflicts',
      'team_track_title': 'Project Progress Tracking (Dev Team)',
      'team_btn_add_task': 'Add Task',
      'team_dialog_add': 'Add Team Task',
      'team_label_name': 'Name',
      'team_label_role': 'Role',
      'team_label_task': 'Task Title',
      'team_label_progress': 'Progress',
      'team_label_high_energy': 'High Efficiency Status:',
      'team_label_due': 'Due Date:',
      'team_card_ongoing': 'In Progress:',
      'team_card_due': 'Due:',

      // Calendar Page
      'calendar_title': 'Smart Schedule',
      'label_duration': 'Duration (mins):',
      'label_start_time': 'Start Time:',
      'color_green': 'Green',
      'color_blue': 'Blue',
      'color_orange': 'Orange',

      // Profile Page
      'profile_title': 'Efficiency Profile',
      'profile_device': 'Device Connection(Apple/Huawei)',
      'profile_connected': 'Connected',
      'profile_auth': 'Third-Party App Authorization (MCP)',
      'settings_title': 'System Settings',
      'settings_language': 'Change Language',
      'settings_notify': 'Notification Management',
      'settings_dark': 'Dark Mode',
      'lang_zh': '🇨🇳 Chinese (Simplified)',
      'lang_en': '🇺🇸 English',
    },
  };

  static String of(
    BuildContext context,
    String key, {
    Map<String, String>? params,
  }) {
    final locale = Localizations.localeOf(context).languageCode;
    final lang = (locale == 'en') ? 'en' : 'zh';
    String text = _data[lang]?[key] ?? key;

    if (params != null) {
      params.forEach((k, v) {
        text = text.replaceAll('{$k}', v);
      });
    }
    return text;
  }
}
