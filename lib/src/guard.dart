import 'command_runner.dart';
import 'git_publisher.dart';

/// The checks every push of a task or planning branch must pass: the branch
/// is not the base branch, the git email has the configured suffix, every
/// commit subject follows the commit rule and no added line holds private
/// data. A blocked task's `wip:` commit and the fixed commit that closes a
/// task are the exceptions to the rule.
class Guard {
  /// The start of the fixed subject of the commit that closes a task.
  static const closingPrefix = 'docs: close task ';

  final RunCommand run;
  final String directory;
  final String baseBranch;
  final List<String> commitTypes;
  final String? emailSuffix;
  final Map<String, RegExp> privatePatterns;

  const Guard({
    required this.run,
    required this.directory,
    required this.baseBranch,
    required this.commitTypes,
    this.emailSuffix,
    this.privatePatterns = const {},
  });

  /// Every problem found, or an empty list when the branch can be pushed.
  Future<List<String>> problems() async {
    Future<String> git(List<String> args) async => (await run('git', args, workingDirectory: directory)).stdout.trim();

    final problems = <String>[];
    final branch = await git(['branch', '--show-current']);
    if ({baseBranch, 'master', 'main', ''}.contains(branch)) problems.add('The branch "$branch" must not be pushed.');

    final email = await git(['config', 'user.email']);
    final suffix = emailSuffix;
    if (suffix != null && !email.endsWith(suffix)) {
      problems.add('The git email "$email" does not end with "$suffix" (git_email_suffix).');
    }

    final subjects = await git(['log', '--format=%s', 'origin/$baseBranch..HEAD']);
    for (final subject in subjects.split('\n').where((line) => line.isNotEmpty)) {
      if (subject.startsWith('wip: ') || subject.startsWith(closingPrefix)) continue;
      if (CommitMessage.problem(subject, types: commitTypes) case final problem?) problems.add(problem);
    }

    final diff = await git(['diff', 'origin/$baseBranch...HEAD', '--unified=0']);
    problems.addAll(DiffScanner.scan(diff, extra: privatePatterns).map((finding) => 'Private data: $finding.'));
    return problems;
  }
}
