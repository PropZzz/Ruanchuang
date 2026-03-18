import 'package:flutter/material.dart';

/// Best-effort tag -> icon mapping for schedule blocks.
IconData iconForTag(String tag) {
  final lower = tag.toLowerCase();

  bool hasAny(List<String> xs) => xs.any((x) => lower.contains(x));

  if (hasAny(['meeting', 'team', 'collab']) ||
      tag.contains('会议') ||
      tag.contains('协作')) {
    return Icons.group;
  }

  if (hasAny(['micro', 'email', 'mail']) ||
      tag.contains('微任务') ||
      tag.contains('邮件')) {
    return Icons.email;
  }

  if (hasAny(['deep', 'architecture', 'arch', 'code', 'dev']) ||
      tag.contains('深度') ||
      tag.contains('架构')) {
    return Icons.code;
  }

  if (hasAny(['urgent']) || tag.contains('紧急')) {
    return Icons.warning_amber_outlined;
  }

  if (hasAny(['goal']) || tag.contains('目标')) {
    return Icons.flag_outlined;
  }

  return Icons.event;
}

