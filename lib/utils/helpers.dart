import 'package:flutter/material.dart';

/// 工具函数：根据标签文本返回对应的 IconData
///
/// 匹配规则：
/// - '会议'/'协作' -> Group Icon
/// - '微任务'/'邮件' -> Email Icon
/// - '深度'/'架构' -> Code Icon
/// - 默认 -> Event Icon
IconData iconForTag(String tag) {
  if (tag.contains('会议') || tag.contains('协作')) return Icons.group;
  if (tag.contains('微任务') || tag.contains('邮件')) return Icons.email;
  if (tag.contains('深度') || tag.contains('架构')) return Icons.code;
  return Icons.event;
}
