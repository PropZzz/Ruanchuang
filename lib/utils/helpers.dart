import 'package:flutter/material.dart';

import '../models/models.dart';
import 'app_strings.dart';

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

/// Best-effort tag -> localized label mapping shared by the focus card, the
/// calendar and the add-entry dialog. Unknown tags render as-is.
String tagLabel(BuildContext context, String tag) {
  switch (tag) {
    case 'General':
      return AppStrings.of(context, 'tag_general');
    case 'Deep Work':
      return AppStrings.of(context, 'tag_deep_work');
    case 'Micro Task':
      return AppStrings.of(context, 'tag_micro_task');
    case 'Routine':
      return AppStrings.of(context, 'tag_routine');
    case 'Urgent':
      return AppStrings.of(context, 'tag_urgent');
    case 'Goal':
      return AppStrings.of(context, 'tag_goal');
  }
  return tag;
}

/// Cognitive load shown for a schedule entry: the stored value when present,
/// otherwise a deterministic estimate from the entry's own tag and duration,
/// so load labels always reflect real entry data instead of a placeholder.
CognitiveLoad effectiveCognitiveLoad(ScheduleEntry entry) {
  final stored = entry.load;
  if (stored != null) return stored;

  final lower = entry.tag.toLowerCase();
  bool hasAny(List<String> xs) => xs.any(lower.contains);
  if (hasAny(['micro', 'email', 'mail']) ||
      entry.tag.contains('微任务') ||
      entry.tag.contains('邮件')) {
    return CognitiveLoad.low;
  }
  if (hasAny(['deep', 'architecture', 'arch', 'code', 'dev']) ||
      entry.tag.contains('深度') ||
      entry.tag.contains('架构') ||
      entry.tag.contains('攻坚')) {
    return CognitiveLoad.high;
  }

  final minutes = ((entry.height / 80.0) * 60.0).round();
  if (minutes >= 60) return CognitiveLoad.high;
  if (minutes >= 25) return CognitiveLoad.medium;
  return CognitiveLoad.low;
}
