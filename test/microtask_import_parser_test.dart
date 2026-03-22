import 'package:flutter_test/flutter_test.dart';

import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/microtask_crystals/microtask_import_parser.dart';

void main() {
  test('parse extracts tasks, tags, minutes, and totals', () {
    const raw = '''
1. 回复客户邮件 10分钟 #收件箱
- 修复登录 Bug 紧急 45分钟 #开发
[ ] 复盘设计笔记 30分钟
''';

    final summary = MicroTaskImportParser.parse(raw);

    expect(summary.suggestions, hasLength(3));
    expect(summary.totalMinutes, 85);
    expect(summary.totalPoints, greaterThan(0));
    expect(summary.headline, contains('3 个任务'));

    final first = summary.suggestions[0];
    expect(first.sourceLine, contains('回复客户邮件'));
    expect(first.task.title, '回复客户邮件');
    expect(first.task.tag, '收件箱');
    expect(first.task.minutes, 10);

    final second = summary.suggestions[1];
    expect(second.task.title, '修复登录 Bug 紧急');
    expect(second.task.tag, '开发');
    expect(second.task.priority, 5);

    final third = summary.suggestions[2];
    expect(third.task.tag, '复盘');
    expect(third.task.minutes, 30);
  });

  test('parse ignores empty or non-task lines', () {
    final summary = MicroTaskImportParser.parse(' \n\n  \t');

    expect(summary.suggestions, isEmpty);
    expect(summary.totalMinutes, 0);
    expect(summary.totalPoints, 0);
    expect(summary.headline, '未找到可导入的任务。');
  });

  test('parse understands Chinese hour and minute formats', () {
    const raw = '''
整理资料 2小时 #整理
''';

    final summary = MicroTaskImportParser.parse(raw);

    expect(summary.suggestions, hasLength(1));
    expect(summary.totalMinutes, 120);
    expect(summary.suggestions.single.task.tag, '整理');
    expect(summary.suggestions.single.task.minutes, 120);
  });

  test('pointsForTask favors short, high-priority tasks', () {
    final fast = MicroTask(
      title: 'Fast inbox reply',
      tag: 'Inbox',
      minutes: 10,
      priority: 5,
    );
    final slow = MicroTask(
      title: 'Slow follow-up',
      tag: 'General',
      minutes: 60,
      priority: 2,
    );

    expect(
      MicroTaskImportParser.pointsForTask(fast),
      greaterThan(MicroTaskImportParser.pointsForTask(slow)),
    );
  });
}
