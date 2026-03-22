import '../../models/models.dart';

class MicroTaskImportSuggestion {
  final MicroTask task;
  final String sourceLine;
  final int points;

  const MicroTaskImportSuggestion({
    required this.task,
    required this.sourceLine,
    required this.points,
  });
}

class MicroTaskImportSummary {
  final List<MicroTaskImportSuggestion> suggestions;
  final int totalMinutes;
  final int totalPoints;
  final String headline;

  const MicroTaskImportSummary({
    required this.suggestions,
    required this.totalMinutes,
    required this.totalPoints,
    required this.headline,
  });
}

class MicroTaskImportParser {
  static final RegExp _bulletPrefix = RegExp(
    r'^\s*(?:[-*]\s*|\d+[.)]\s*|\[[xX ]\]\s*)',
  );
  static final RegExp _minutePattern = RegExp(
    r'(\d{1,3})\s*(?:m|min|mins|minutes|分钟)(?=\s|$|[，,。；;:：])',
    caseSensitive: false,
  );
  static final RegExp _hourMinutePattern = RegExp(
    r'(\d{1,2})\s*小时(?:\s*(\d{1,3})\s*分钟?)?',
    caseSensitive: false,
  );
  static final RegExp _hourPattern = RegExp(r'(\d{1,2})\s*小时\b');
  static final RegExp _tagPattern = RegExp(r'(?:#|@)([^\s#@]+)');
  static final RegExp _multiSpace = RegExp(r'\s+');

  static MicroTaskImportSummary parse(String raw) {
    final suggestions = <MicroTaskImportSuggestion>[];
    final lines = raw.split(RegExp(r'[\r\n]+'));

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final suggestion = _parseLine(line, index: i);
      if (suggestion != null) {
        suggestions.add(suggestion);
      }
    }

    final totalMinutes = suggestions.fold<int>(
      0,
      (sum, suggestion) => sum + suggestion.task.minutes,
    );
    final totalPoints = suggestions.fold<int>(
      0,
      (sum, suggestion) => sum + suggestion.points,
    );

    final headline = suggestions.isEmpty
        ? '未找到可导入的任务。'
        : '${suggestions.length} 个任务 | $totalMinutes 分钟 | +$totalPoints 积分';

    return MicroTaskImportSummary(
      suggestions: List<MicroTaskImportSuggestion>.unmodifiable(suggestions),
      totalMinutes: totalMinutes,
      totalPoints: totalPoints,
      headline: headline,
    );
  }

  static int pointsForTask(MicroTask task) {
    final minutes = task.minutes.clamp(1, 24 * 60).toInt();
    final priority = task.priority.clamp(1, 5).toInt();

    final durationBonus = minutes <= 10
        ? 5
        : minutes <= 20
            ? 4
            : minutes <= 40
                ? 2
                : 1;
    final tagBonus = _bonusForTag(task.tag);

    return (priority * 2 + durationBonus + tagBonus).clamp(1, 20).toInt();
  }

  static MicroTaskImportSuggestion? _parseLine(String line, {required int index}) {
    var cleaned = line.replaceFirst(_bulletPrefix, '').trim();
    cleaned = cleaned.replaceAll(_multiSpace, ' ');
    if (cleaned.isEmpty) return null;

    final minutes = _extractMinutes(cleaned) ?? _estimateMinutes(cleaned);
    final tag = _extractTag(cleaned) ?? _inferTag(cleaned);
    final title = _extractTitle(cleaned);
    if (title.isEmpty) return null;

    final task = MicroTask(
      title: title,
      tag: tag,
      minutes: minutes,
      priority: _inferPriority(cleaned, minutes: minutes, index: index),
    );

    return MicroTaskImportSuggestion(
      task: task,
      sourceLine: line,
      points: pointsForTask(task),
    );
  }

  static int? _extractMinutes(String line) {
    final hourMinuteMatch = _hourMinutePattern.firstMatch(line);
    if (hourMinuteMatch != null) {
      final hours = int.tryParse(hourMinuteMatch.group(1) ?? '');
      final extraMinutes = int.tryParse(hourMinuteMatch.group(2) ?? '') ?? 0;
      if (hours != null) {
        return (hours * 60 + extraMinutes).clamp(1, 24 * 60).toInt();
      }
    }

    final match = _minutePattern.firstMatch(line);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  static String? _extractTag(String line) {
    final match = _tagPattern.firstMatch(line);
    if (match == null) return null;
    final tag = match.group(1)?.trim().replaceAll(RegExp(r'[，,。；;:：]+$'), '');
    return (tag == null || tag.isEmpty) ? null : tag;
  }

  static String _inferTag(String line) {
    final lower = line.toLowerCase();
    if (line.contains('邮件') || line.contains('邮箱') || line.contains('收件箱') ||
        lower.contains('email') || lower.contains('mail') || lower.contains('inbox')) {
      return '收件箱';
    }
    if (line.contains('电话') || line.contains('通话') || lower.contains('call') || lower.contains('phone')) {
      return '通话';
    }
    if (line.contains('复盘') || line.contains('评审') || line.contains('检查') || lower.contains('review')) {
      return '复盘';
    }
    if (line.contains('设计') || line.contains('需求') || line.contains('方案') || lower.contains('design') || lower.contains('spec')) {
      return '设计';
    }
    if (line.contains('修复') || line.contains('bug') || line.contains('故障') || lower.contains('fix')) {
      return '修复';
    }
    if (line.contains('学习') || line.contains('阅读') || lower.contains('study') || lower.contains('read')) {
      return '学习';
    }
    if (line.contains('整理') || line.contains('归档')) {
      return '整理';
    }
    return '已导入';
  }

  static String _extractTitle(String line) {
    var title = line;
    title = title.replaceAll(_hourMinutePattern, ' ');
    title = title.replaceAll(_minutePattern, ' ');
    title = title.replaceAll(_hourPattern, ' ');
    title = title.replaceAll(_tagPattern, ' ');
    title = title.replaceAll(RegExp(r'\[[xX ]\]'), ' ');
    title = title.replaceAll(RegExp(r'^[\s>]+'), '');
    title = title.replaceAll(RegExp(r'^[\-\*\d\.\)\(]+\s*'), '');
    title = title.replaceAll(_multiSpace, ' ').trim();
    return title;
  }

  static int _inferPriority(
    String line, {
    required int minutes,
    required int index,
  }) {
    final lower = line.toLowerCase();
    if (line.contains('紧急') ||
        line.contains('立即') ||
        line.contains('今天') ||
        line.contains('尽快') ||
        lower.contains('urgent') ||
        lower.contains('asap') ||
        lower.contains('now') ||
        lower.contains('today')) {
      return 5;
    }
    if (line.contains('重要') ||
        line.contains('必须') ||
        line.contains('关键') ||
        lower.contains('important') ||
        lower.contains('must') ||
        lower.contains('critical')) {
      return 4;
    }
    if (line.contains('稍后') ||
        line.contains('可选') ||
        line.contains('也许') ||
        line.contains('可以晚点') ||
        lower.contains('later') ||
        lower.contains('optional') ||
        lower.contains('maybe')) {
      return 2;
    }
    if (minutes <= 10) {
      return 4;
    }
    if (minutes <= 20) {
      return 3;
    }
    if (index == 0) {
      return 4;
    }
    return 3;
  }

  static int _estimateMinutes(String line) {
    final lower = line.toLowerCase();
    if (line.contains('深度工作') ||
        line.contains('设计') ||
        line.contains('需求') ||
        line.contains('方案') ||
        lower.contains('deep work') ||
        lower.contains('design') ||
        lower.contains('spec') ||
        lower.contains('plan')) {
      return 45;
    }
    if (line.contains('复盘') || line.contains('检查') ||
        lower.contains('review') || lower.contains('check')) {
      return 20;
    }
    if (line.contains('邮件') || line.contains('收件箱') ||
        lower.contains('email') || lower.contains('mail') || lower.contains('inbox')) {
      return 10;
    }
    if (line.contains('电话') || line.contains('通话') ||
        lower.contains('call') || lower.contains('phone')) {
      return 15;
    }
    final hourMatch = _hourPattern.firstMatch(line);
    if (hourMatch != null) {
      final hours = int.tryParse(hourMatch.group(1) ?? '');
      if (hours != null && hours > 0) {
        return (hours * 60).clamp(1, 24 * 60).toInt();
      }
    }
    if (line.length > 80) {
      return 30;
    }
    return 15;
  }

  static int _bonusForTag(String tag) {
    final lower = tag.toLowerCase();
    if (tag.contains('收件箱') || tag.contains('邮件') || lower.contains('inbox')) return 2;
    if (tag.contains('复盘') || lower.contains('review')) return 2;
    if (tag.contains('修复') || lower.contains('fix')) return 2;
    if (tag.contains('设计') || lower.contains('design')) return 1;
    return 0;
  }
}
