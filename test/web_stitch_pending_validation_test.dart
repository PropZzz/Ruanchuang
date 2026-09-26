import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('urgent task form does not claim results before requesting the server', () {
    final html = File(
      'web/stitch/mobile/insert-urgent-task-drawer/index.html',
    ).readAsStringSync();

    expect(html, contains('提交后由服务端按硬截止与现有日程生成真实救援方案'));
    expect(html, contains('等待服务端分析当前日程'));
    expect(html, isNot(contains('时空引擎实时就绪')));
    expect(html, isNot(contains('探测到 2 处时空硬性冲突')));
    expect(html, isNot(contains('3 组解集')));
  });

  test('new schedule form waits for server validation before showing conflict status', () {
    final html = File(
      'web/stitch/mobile/create-schedule-drawer/index.html',
    ).readAsStringSync();

    expect(html, contains('待服务端校验'));
    expect(html, contains('保存后由服务端校验时段与日程约束'));
    expect(html, isNot(contains('算法时空适配检查通过')));
    expect(html, isNot(contains('零冲突')));
  });

  test('urgent task deadline is editable and sent to the rescue endpoint', () {
    final form = File(
      'web/stitch/mobile/insert-urgent-task-drawer/index.html',
    ).readAsStringSync();
    final router = File('web/stitch/router.js').readAsStringSync();

    expect(form, contains('id="urgent-task-deadline-input"'));
    expect(form, contains('type="datetime-local"'));
    expect(form, isNot(contains('今天 (09-25)')));
    expect(form, isNot(contains('仅剩 3h 15m')));
    expect(
      router.contains("document.getElementById('urgent-task-deadline-input')"),
      isTrue,
    );
    expect(router.contains('due: dueDate.toISOString()'), isTrue);
  });

  test('mobile rescue comparison never reports a local demo apply or undo', () {
    final html = File(
      'web/stitch/mobile/urgent-rescue-comparison/index.html',
    ).readAsStringSync();

    expect(html, isNot(contains('SNAP-9284')));
    expect(html, isNot(contains('已成功触发快照回滚')));
  });

  test('mobile calendar sends rescue entry to the real task form', () {
    final html = File('web/stitch/mobile/schedule/index.html').readAsStringSync();
    final router = File('web/stitch/router.js').readAsStringSync();

    expect(html, contains('schedule-conflict-status'));
    expect(html, contains('生成服务端救援方案'));
    expect(html, contains('aria-label="新增日程"'));
    expect(html, contains('id="mobile-rescue-generate"'));
    expect(html, isNot(contains('立即应用方案 A · 重构今日时间地图')));
    expect(html, isNot(contains('智能救援方案已就绪')));
    expect(html, isNot(contains('30 秒内一键撤销')));
    expect(router.contains('rescueSheet.hidden = true'), isTrue);
    expect(router.contains('schedule-create-urgent-task'), isTrue);
    expect(router.contains("button.id === 'mobile-rescue-generate'"), isTrue);
    expect(router.contains("button.dataset.scheduleView"), isTrue);
    expect(router.contains("button.dataset.scheduleDay"), isTrue);
  });

  test('web date payloads use the local calendar day', () {
    final router = File('web/stitch/router.js').readAsStringSync();
    final schedule = File('web/stitch/mobile/create-schedule-drawer/index.html').readAsStringSync();
    expect(router, contains('function todayIso() {\n    return localIsoDate(new Date());'));
    expect(router.contains("action === 'microtask-quick-add'"), isTrue);
    expect(router.contains("action === 'microtask-sweep'"), isTrue);
    expect(router.contains("button.id === 'btn-quick-add'"), isTrue);
    expect(router.contains("button.id === 'btn-sweep-start'"), isTrue);
    expect(router.contains("activeRoute === 'schedule' && label.includes('立即对比并执行救援方案')"), isTrue);
    expect(router.contains('通知推送接口尚未接入'), isTrue);
    expect(router.contains('导出离线备份|诊断日志入口'), isTrue);
    expect(schedule, contains('id="schedule-date-label"'));
    expect(schedule, isNot(contains('2026年9月25日 周五')));
  });

  test('rescue router hydrates mobile cards and undoes the latest server snapshot', () {
    final router = File('web/stitch/router.js').readAsStringSync();

    expect(router.contains("querySelectorAll('.plan-card')"), isTrue);
    expect(router.contains("'/schedule/rescue/undo'"), isTrue);
    expect(router.contains("filter((entry) => entry.day === rescueState.day)"), isTrue);
    expect(router.contains('rememberRescueSnapshot(applied.snapshotId)'), isTrue);
    expect(router.contains('ruanchuang_rescue_snapshots:\${identity}'), isTrue);
    expect(router.contains('rescueSnapshotMemory'), isTrue);
    expect(router.contains('mobile-rescue-undo'), isTrue);
    expect(router.contains('rescueSheet.hidden = true'), isTrue);
    expect(router.contains("url.searchParams.set('v', routeAssetVersion)"), isTrue);
  });
}
