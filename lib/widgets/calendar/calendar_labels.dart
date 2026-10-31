import 'package:flutter/material.dart';
import '../../utils/app_strings.dart';
import '../schedule_timeline.dart';

String calendarEntryTitle(BuildContext context, String title) {
  switch (title) {
    case 'Architecture design':
      return AppStrings.of(context, 'calendar_seed_architecture_design');
    case 'Email triage':
      return AppStrings.of(context, 'calendar_seed_email_triage');
    case 'Spec review':
      return AppStrings.of(context, 'calendar_seed_spec_review');
    case 'Implementation sprint':
      return AppStrings.of(context, 'calendar_seed_implementation_sprint');
  }
  return title;
}

String calendarViewLabel(BuildContext context, ScheduleTimelineView view) {
  final isEn = Localizations.localeOf(context).languageCode == 'en';
  switch (view) {
    case ScheduleTimelineView.day:
      return isEn ? 'Day' : '日';
    case ScheduleTimelineView.week:
      return isEn ? 'Week' : '周';
    case ScheduleTimelineView.month:
      return isEn ? 'Month' : '月';
    case ScheduleTimelineView.gantt:
      return isEn ? 'Gantt' : '甘特';
  }
}

String calendarFieldLabel(BuildContext context, ScheduleTimelineField field) {
  final isEn = Localizations.localeOf(context).languageCode == 'en';
  switch (field) {
    case ScheduleTimelineField.time:
      return isEn ? 'Time' : '时间';
    case ScheduleTimelineField.tag:
      return isEn ? 'Tag' : '标签';
    case ScheduleTimelineField.status:
      return isEn ? 'Status' : '状态';
    case ScheduleTimelineField.reminder:
      return isEn ? 'Reminder' : '提醒';
    case ScheduleTimelineField.goal:
      return isEn ? 'Goal' : '目标';
  }
}
