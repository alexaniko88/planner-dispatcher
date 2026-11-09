import 'dart:io';

import 'package:test/test.dart';

import 'package:planner_dispatcher/src/backlog_mover.dart';
import 'package:planner_dispatcher/src/command_runner.dart';

String _git(String directory, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: directory);
  if (result.exitCode != 0) fail('git ${args.join(' ')} failed: ${result.stderr}');
  return (result.stdout as String).trim();
}

void main() {
  late String repo;
  late BacklogMover mover;

  void write(String path, String text) {
    File('$repo/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  String read(String path) => File('$repo/$path').readAsStringSync();

  bool exists(String path) => FileSystemEntity.typeSync('$repo/$path') != FileSystemEntityType.notFound;

  void commit() {
    _git(repo, ['add', '-A']);
    _git(repo, ['commit', '-q', '-m', 'seed']);
  }

  setUp(() {
    final directory = Directory.systemTemp.createTempSync('backlog_mover_test_');
    addTearDown(() => directory.deleteSync(recursive: true));
    repo = directory.path;
    _git(repo, ['init', '-q', '-b', 'main']);
    _git(repo, ['config', 'user.email', 'test@users.noreply.github.com']);
    _git(repo, ['config', 'user.name', 'Test']);
    mover = BacklogMover(workspace: repo, run: runSystemCommand);
  });

  test('close-finished closes only finished stories and epics', () async {
    write('docs/backlog/epic-a/index.md', '1. [S](stories/story-01-s/index.md)\n');
    write('docs/backlog/epic-a/stories/story-01-s/index.md', 'Epic: [A](../../index.md)\n');
    write('docs/backlog/epic-a/stories/story-01-s/done/task-01-t/index.md', 'Story: [S](../../index.md)\n');
    write('docs/backlog/epic-b/stories/story-01-done/done/task-01-t/index.md', '# T\n');
    write('docs/backlog/epic-b/stories/story-02-open/task-01-t/index.md', '# T\n');
    write('docs/backlog/epic-c/stories/story-01-empty/index.md', '# S\n');
    commit();

    final moves = await mover.closeFinished();

    expect(moves, {
      'docs/backlog/epic-a/stories/story-01-s': 'docs/backlog/epic-a/stories/done/story-01-s',
      'docs/backlog/epic-a': 'docs/backlog/done/epic-a',
      'docs/backlog/epic-b/stories/story-01-done': 'docs/backlog/epic-b/stories/done/story-01-done',
    });
    expect(read('docs/backlog/done/epic-a/index.md'), contains('(stories/done/story-01-s/index.md)'));
    expect(read('docs/backlog/done/epic-a/stories/done/story-01-s/index.md'), contains('[A](../../../index.md)'));
    expect(exists('docs/backlog/epic-b/stories/story-02-open'), isTrue);
    expect(exists('docs/backlog/epic-c/stories/story-01-empty'), isTrue);
  });

  test('reopen moves a closed story and its closed epic out of done/, keeping done tasks', () async {
    write('docs/backlog/done/epic-a/index.md', '1. [S](stories/done/story-01-s/index.md)\n');
    write('docs/backlog/done/epic-a/stories/done/story-01-s/index.md', 'Epic: [A](../../../index.md)\n');
    write('docs/backlog/done/epic-a/stories/done/story-01-s/done/task-01-t/index.md', 'Story: [S](../../index.md)\n');
    write('docs/backlog/bugs/index.md', 'See [S](../done/epic-a/stories/done/story-01-s/index.md)\n');
    commit();

    final target = await mover.reopen('docs/backlog/done/epic-a/stories/done/story-01-s');

    expect(target, 'docs/backlog/epic-a/stories/story-01-s');
    expect(exists('docs/backlog/epic-a/stories/story-01-s/done/task-01-t/index.md'), isTrue);
    expect(exists('docs/backlog/done/epic-a'), isFalse);
    expect(read('docs/backlog/epic-a/index.md'), contains('(stories/story-01-s/index.md)'));
    expect(read('docs/backlog/epic-a/stories/story-01-s/index.md'), contains('[A](../../index.md)'));
    expect(read('docs/backlog/epic-a/stories/story-01-s/done/task-01-t/index.md'), contains('[S](../../index.md)'));
    expect(read('docs/backlog/bugs/index.md'), contains('(../epic-a/stories/story-01-s/index.md)'));
  });

  test('reopen of an open folder changes nothing, and of a missing one fails', () async {
    write('docs/backlog/epic-a/stories/story-01-s/index.md', '# S\n');
    commit();

    expect(await mover.reopen('docs/backlog/epic-a/stories/story-01-s'), 'docs/backlog/epic-a/stories/story-01-s');
    expect(() => mover.reopen('docs/backlog/epic-x'), throwsStateError);
  });
}
