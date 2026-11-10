import 'command_runner.dart';
import 'git_publisher.dart';

/// The checks every push of a task or planning branch must pass: the branch
/// is not the base branch, the git email of the config and of every commit
/// has the configured suffix, every commit subject follows the commit rule
/// and no line any commit adds holds private data. A blocked task's `wip:` commit and the fixed commit that closes a
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

  /// Every problem found, or an empty list when the branch can be pushed. A
  /// git command that fails is a problem too, so a wrong `base_branch` never
  /// lets a branch through unchecked.
  Future<List<String>> problems() async {
    final problems = <String>[];
    Future<String> git(List<String> args) async {
      final result = await run('git', args, workingDirectory: directory);
      if (!result.ok) {
        problems.add('Could not check the branch: "git ${args.join(' ')}" failed: ${result.stderr.trim()}');
      }
      return result.stdout.trim();
    }

    final branch = await git(['branch', '--show-current']);
    if ({baseBranch, 'master', 'main', ''}.contains(branch)) problems.add('The branch "$branch" must not be pushed.');

    final suffix = emailSuffix;
    final range = 'origin/$baseBranch..HEAD';
    // The author and committer of every commit, not only the current config.
    final commits = await git(['log', '--format=%ae%x09%ce%x09%s', range]);
    final emails = <String>{
      if (suffix != null) await git(['config', 'user.email']),
    };
    for (final line in commits.split('\n').where((line) => line.isNotEmpty)) {
      final [author, committer, ...rest] = line.split('\t');
      final subject = rest.join('\t');
      if (suffix != null) emails.addAll([author, committer]);
      if (subject.startsWith('wip: ') || subject.startsWith(closingPrefix)) continue;
      if (CommitMessage.problem(subject, types: commitTypes) case final problem?) problems.add(problem);
    }
    if (suffix != null) {
      for (final email in emails.where((email) => !email.endsWith(suffix))) {
        problems.add('The git email "$email" does not end with "$suffix" (git_email_suffix).');
      }
    }

    // Every commit, so data added and removed again is still found. Plain text
    // output: no colors, no external diff and no binary shortcut.
    final patches = await git([
      'log',
      '-p',
      '--unified=0',
      '--format=',
      '--no-color',
      '--no-ext-diff',
      '--no-textconv',
      '--text',
      range,
    ]);
    problems.addAll(DiffScanner.scan(patches, extra: privatePatterns).map((finding) => 'Private data: $finding.'));
    return problems;
  }
}
