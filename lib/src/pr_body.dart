import 'task.dart';

/// A golden image that changed in the branch.
class GoldenChange {
  final String path;

  /// False for a new image: there is nothing to show as "before".
  final bool existedBefore;

  const GoldenChange({required this.path, required this.existedBefore});
}

/// The PR description of a finished task: a short summary with the task link,
/// the acceptance list, the visual changes when goldens changed, the checks,
/// and the points to review only when there are some. It carries no
/// attribution line.
class PrBody {
  /// [baseSha] and [headSha] pin the links, so they never change.
  static String build({
    required Task task,
    required String summary,
    required String checks,
    required String pointsToReview,
    required List<GoldenChange> goldens,
    required String slug,
    required String baseSha,
    required String headSha,
    required String taskPath,
  }) {
    final blob = 'https://github.com/$slug/blob';
    final points = pointsToReview.trim();
    final lines = [
      '## Summary',
      '',
      summary.trim().isEmpty ? task.title : summary.trim(),
      '',
      'Task: [${task.label}]($blob/$headSha/$taskPath)',
      '',
      '## Acceptance',
      '',
      ...task.acceptance.map((line) => line.replaceFirst('- [ ]', '- [x]')),
      if (goldens.isNotEmpty) ...[
        '',
        '## Visual changes',
        '',
        '| Screen | Before | After |',
        '| --- | --- | --- |',
        for (final golden in goldens)
          '| ${golden.path.split('/').last} | '
              '${golden.existedBefore ? '![before]($blob/$baseSha/${golden.path}?raw=true)' : 'new'} | '
              '![after]($blob/$headSha/${golden.path}?raw=true) |',
      ],
      '',
      '## Checks',
      '',
      checks.trim(),
      if (points.isNotEmpty && points.toLowerCase() != 'none' && points.toLowerCase() != 'none.') ...[
        '',
        '## Points to review',
        '',
        points,
      ],
    ];
    return '${lines.join('\n')}\n';
  }
}
