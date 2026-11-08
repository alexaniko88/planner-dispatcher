import 'command_runner.dart';
import 'pr_description.dart';

/// The commit subject rule for the commit lines a stage reports. The types
/// come from the project's `commit_types`.
class CommitMessage {
  /// Why [subject] is not a valid first line, or null when it is.
  static String? problem(String subject, {required List<String> types}) {
    if (subject.isEmpty) return 'The commit message is empty.';
    if (subject.length > 100) return 'The commit message is longer than 100 characters.';
    final pattern = RegExp('^(${types.map(RegExp.escape).join('|')}): [a-z0-9`].*[^.]\$');
    if (!pattern.hasMatch(subject)) {
      return 'The commit message "$subject" must be "<type>: <description>", lowercase, with no final period.';
    }
    return null;
  }
}

/// Looks for private data in the lines a branch adds. The patterns are built
/// from parts so this file does not match its own scan.
class DiffScanner {
  static final Map<String, RegExp> _rules = {
    'a local home path': RegExp(
      '/Us'
      'ers/[A-Za-z]',
    ),
    'a private key': RegExp(
      '-----BEGIN [A-Z ]*PRIVATE '
      'KEY-----',
    ),
    'a GitHub token': RegExp('gh[pousr]_[A-Za-z0-9]{30,}'),
    'a secret key': RegExp('sk-[A-Za-z0-9]{20,}'),
  };

  /// One text per finding: the file and what was found. [diff] is
  /// `git diff --unified=0` output. [extra] adds the project's
  /// `private_patterns`, keyed by what they find.
  static List<String> scan(String diff, {Map<String, RegExp> extra = const {}}) {
    final rules = {..._rules, ...extra};
    final findings = <String>[];
    var file = '';
    for (final line in diff.split('\n')) {
      if (line.startsWith('+++ ')) {
        file = line.substring(4).replaceFirst(RegExp(r'^b/'), '');
        continue;
      }
      if (!line.startsWith('+')) continue;
      for (final MapEntry(:key, :value) in rules.entries) {
        if (value.hasMatch(line)) findings.add('$file has $key');
      }
    }
    return findings;
  }
}

/// Every write to git and GitHub of a run. Only the script does them; the AI
/// tools run in a sandbox that cannot write to `.git`.
class GitPublisher {
  final String workspace;
  final RunCommand run;
  final String baseBranch;

  /// Where the project keeps its golden images, or null when it has none.
  final String? goldensDir;

  const GitPublisher({required this.workspace, required this.run, required this.baseBranch, this.goldensDir});

  Future<CommandResult> _git(List<String> args) => run('git', args, workingDirectory: workspace);

  /// Stages everything and commits. Returns an error text, or null on success
  /// or when there was nothing to commit.
  Future<String?> commitAll({required String subject, required String trailer}) async {
    final add = await _git(['add', '-A']);
    if (!add.ok) return 'git add failed: ${add.stderr}';
    final status = await _git(['status', '--porcelain']);
    if (status.stdout.trim().isEmpty) return null;
    final commit = await _git(['commit', '-q', '-m', subject, '-m', trailer]);
    return commit.ok ? null : 'git commit failed: ${commit.stderr}';
  }

  Future<String> headSha() async => (await _git(['rev-parse', 'HEAD'])).stdout.trim();

  Future<String> baseSha() async => (await _git(['rev-parse', 'origin/$baseBranch'])).stdout.trim();

  /// The lines the branch adds compared with the base branch on the remote.
  Future<String> addedLinesDiff() async => (await _git(['diff', 'origin/$baseBranch...HEAD', '--unified=0'])).stdout;

  /// The golden images that were added or changed. Empty when the project
  /// has no golden folder.
  Future<List<GoldenChange>> changedGoldens() async {
    final folder = goldensDir;
    if (folder == null) return const [];
    final result = await _git(['diff', '--name-status', 'origin/$baseBranch...HEAD', '--', folder]);
    final changes = <GoldenChange>[];
    for (final line in result.stdout.split('\n')) {
      final parts = line.split('\t');
      if (parts.length < 2 || !parts.last.endsWith('.png')) continue;
      if (parts.first == 'D') continue;
      changes.add(GoldenChange(path: parts.last, existedBefore: parts.first != 'A'));
    }
    return changes;
  }

  /// Pushes HEAD to [branch]. It never pushes to the base branch, `master` or
  /// `main`.
  Future<String?> push(String branch) async {
    if ({baseBranch, 'master', 'main', ''}.contains(branch)) return 'Refusing to push to "$branch".';
    final result = await _git(['push', 'origin', 'HEAD:refs/heads/$branch']);
    return result.ok ? null : 'git push failed: ${result.stderr}';
  }

  /// Opens the PR and returns its URL, or an error text starting with `error:`.
  Future<String> openPullRequest({
    required String branch,
    required String title,
    required String bodyFile,
  }) async {
    final result = await run(
      'gh',
      ['pr', 'create', '--base', baseBranch, '--head', branch, '--title', title, '--body-file', bodyFile],
      workingDirectory: workspace,
    );
    if (!result.ok) return 'error: ${result.stderr}';
    return result.stdout.trim().split('\n').last;
  }
}
