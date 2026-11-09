// Checks how tasks are read and which one can start next.
import 'package:test/test.dart';

import 'package:planner_dispatcher/src/task.dart';
import 'package:planner_dispatcher/src/task_loader.dart';
import 'package:planner_dispatcher/src/task_selector.dart';

String _task({
  required String id,
  String status = 'ready',
  String dependsOn = '[]',
  String touches = '[lib/a/**]',
  String title = 'Do it',
}) {
  return '---\nid: $id\nstatus: $status\ntype: feat\ndepends-on: $dependsOn\ntouches: $touches\n---\n\n# $title\n';
}

Future<List<Task>> _load(Map<String, String> files) => TaskLoader(() async => files).load();

void main() {
  group('Task', () {
    test('reads the front matter and builds the branch name and the label', () {
      final task = Task.tryParse(
        path: 'docs/backlog/epic-templates/stories/story-03-own/task-02-store-custom/index.md',
        text: _task(id: 'TPL-03-02', dependsOn: '[TPL-03-01]', title: 'Store custom templates'),
      );

      expect(task?.id, 'TPL-03-02');
      expect(task?.dependsOn, ['TPL-03-01']);
      expect(task?.branch, 'feat/tpl-03-02-store-custom');
      expect(task?.label, 'Store custom templates (TPL-03-02)');
      expect(task?.isDone, isFalse);
    });

    test('a task folder in the older layout keeps the same branch name', () {
      final task = Task.tryParse(
        path: 'docs/backlog/templates/stories/03-own/02-store-custom/index.md',
        text: _task(id: 'TPL-03-02'),
      );

      expect(task?.branch, 'feat/tpl-03-02-store-custom');
    });

    test('a scalar depends-on is a one-item list, and unindented block items are read', () {
      final task = Task.tryParse(
        path: 'docs/backlog/x/stories/01-s/01-t/index.md',
        text: '---\nid: X-01-01\ndepends-on: TPL-01-01\ntouches:\n- lib/a.dart\n---\n\n# T\n',
      );

      expect(task?.dependsOn, ['TPL-01-01']);
      expect(task?.touches, ['lib/a.dart']);
    });

    test('an epic or story index without an id is not a task', () {
      expect(Task.tryParse(path: 'docs/backlog/x/index.md', text: '---\nabbr: X\n---\n# Epic\n'), isNull);
    });

    test('a backlog folder named done does not make its tasks done', () {
      final task = Task.tryParse(
        path: 'work/done/backlog/epic-x/stories/story-01-s/task-01-t/index.md',
        text: _task(id: 'X-01-01'),
        root: 'work/done/backlog',
      );

      expect(task?.isDone, isFalse);
    });

    test('a task under done/ is done, also when its story or epic is closed', () {
      for (final path in [
        'docs/backlog/epic-x/stories/story-01-s/done/task-01-t/index.md',
        'docs/backlog/epic-x/stories/done/story-01-s/done/task-01-t/index.md',
        'docs/backlog/done/epic-x/stories/done/story-01-s/done/task-01-t/index.md',
      ]) {
        expect(
          Task.tryParse(
            path: path,
            text: _task(id: 'X-01-01'),
          )?.isDone,
          isTrue,
          reason: path,
        );
      }
    });
  });

  group('TaskLoader', () {
    test('keeps only tasks and sorts them by path', () async {
      final tasks = await _load({
        'docs/backlog/b/stories/01-s/01-t/index.md': _task(id: 'B-01-01'),
        'docs/backlog/a/index.md': '---\nabbr: A\n---\n# Epic\n',
        'docs/backlog/a/stories/01-s/01-t/index.md': _task(id: 'A-01-01'),
      });

      expect(tasks.map((task) => task.id), ['A-01-01', 'B-01-01']);
    });
  });

  group('TaskSelector', () {
    const root = 'docs/backlog/e/stories/01-s';

    test('a draft task is never offered', () async {
      final tasks = await _load({'$root/01-a/index.md': _task(id: 'E-01-01', status: 'draft')});

      expect(TaskSelector(tasks: tasks).next(), isNull);
    });

    test('waits for a dependency until it is in done/', () async {
      final files = {
        '$root/01-a/index.md': _task(id: 'E-01-01'),
        '$root/02-b/index.md': _task(id: 'E-01-02', dependsOn: '[E-01-01]', touches: '[lib/b/**]'),
      };
      var selector = TaskSelector(tasks: await _load(files));

      expect(selector.candidates().map((task) => task.id), ['E-01-01']);
      expect(selector.blockReason(selector.tasks[1]), 'waits for E-01-01');

      files['$root/done/01-a/index.md'] = _task(id: 'E-01-01', status: 'done');
      files.remove('$root/01-a/index.md');
      selector = TaskSelector(tasks: await _load(files));

      expect(selector.next()?.id, 'E-01-02');
    });

    test('a task that overlaps a running task waits', () async {
      final tasks = await _load({
        '$root/01-a/index.md': _task(id: 'E-01-01', touches: '[lib/a/**]'),
        '$root/02-b/index.md': _task(id: 'E-01-02', touches: '[lib/a/x.dart]'),
        '$root/03-c/index.md': _task(id: 'E-01-03', touches: '[lib/c/**]'),
      });
      final selector = TaskSelector(tasks: tasks, busyIds: {'E-01-01'});

      expect(selector.candidates().map((task) => task.id), ['E-01-03']);
      expect(selector.blockReason(tasks[1]), 'overlaps with running E-01-01');
    });

    test('a task with a branch or an open PR is busy', () async {
      final tasks = await _load({'$root/01-a/index.md': _task(id: 'E-01-01')});
      final busy = TaskSelector.busyIdsFromBranches(tasks: tasks, branches: ['feat/e-01-01-a', 'fix/other']);

      expect(busy, {'E-01-01'});
      expect(TaskSelector(tasks: tasks, busyIds: busy).next(), isNull);
    });

    test('a skipped task is not offered', () async {
      final tasks = await _load({
        '$root/01-a/index.md': _task(id: 'E-01-01'),
        '$root/02-b/index.md': _task(id: 'E-01-02', touches: '[lib/b/**]'),
      });

      expect(TaskSelector(tasks: tasks).next(skipped: {'E-01-01'})?.id, 'E-01-02');
    });
  });
}
