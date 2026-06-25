import 'package:flutter_test/flutter_test.dart';
import 'package:llm_replay_eval/llm_replay_eval.dart';

void main() {
  group('EvalSuite', () {
    test('runs cases, aggregates pass rate, and records outputs', () async {
      final session = ReplaySession(
        cassette: Cassette('suite'),
        mode: ReplayMode.record,
      );

      final suite = EvalSuite('greetings', [
        EvalCase(
          name: 'says hello',
          request: {'prompt': 'greet'},
          infer: () async => 'Hello there!',
          checks: [ContainsText('Hello')],
        ),
        EvalCase(
          name: 'valid json',
          request: {'prompt': 'json'},
          infer: () async => '{"ok":true}',
          checks: [
            IsValidJson(),
            JsonHasKeys(['ok']),
          ],
        ),
        EvalCase(
          name: 'fails on purpose',
          request: {'prompt': 'bad'},
          infer: () async => 'nope',
          checks: [ContainsText('expected-but-absent')],
        ),
      ]);

      final report = await suite.run(session);
      expect(report.total, 3);
      expect(report.passedCount, 2);
      expect(report.passRate, closeTo(2 / 3, 1e-9));
      expect(report.passed, isFalse);
    });

    test('report.summary lists failures with their reasons', () async {
      final session = ReplaySession(
        cassette: Cassette('suite'),
        mode: ReplayMode.record,
      );
      final suite = EvalSuite('s', [
        EvalCase(
          name: 'c1',
          request: {'p': 1},
          infer: () async => 'abc',
          checks: [ContainsText('xyz')],
        ),
      ]);
      final summary = (await suite.run(session)).summary();
      expect(summary, contains('Eval "s": 0/1'));
      expect(summary, contains('✗ c1'));
      expect(summary, contains('contains "xyz"'));
    });

    test('report.toJson is structured for agents/CI', () async {
      final session = ReplaySession(
        cassette: Cassette('suite'),
        mode: ReplayMode.record,
      );
      final suite = EvalSuite('s', [
        EvalCase(
          name: 'c1',
          request: {'p': 1},
          infer: () async => 'hello',
          checks: [ContainsText('hello')],
        ),
      ]);
      final json = (await suite.run(session)).toJson();
      expect(json['suite'], 's');
      expect(json['passRate'], 1.0);
      expect((json['cases']! as List), hasLength(1));
    });

    test('an empty suite passes with rate 1.0', () async {
      final session = ReplaySession(
        cassette: Cassette('e'),
        mode: ReplayMode.replay,
      );
      final report = await EvalSuite('empty', []).run(session);
      expect(report.passed, isTrue);
      expect(report.passRate, 1.0);
    });

    test('a fully cassetted suite replays offline end-to-end', () async {
      // Record once.
      final rec = ReplaySession(
        cassette: Cassette('e2e'),
        mode: ReplayMode.record,
      );
      var inferCalls = 0;
      List<EvalCase> cases() => [
        EvalCase(
          name: 'q',
          request: {'prompt': 'capital of France'},
          infer: () async {
            inferCalls++;
            return 'Paris';
          },
          checks: [ContainsText('Paris')],
        ),
      ];
      await EvalSuite('e2e', cases()).run(rec);
      expect(inferCalls, 1);

      // Replay: no inference calls, still passes.
      final replay = ReplaySession(
        cassette: rec.cassette,
        mode: ReplayMode.replay,
      );
      final report = await EvalSuite('e2e', cases()).run(replay);
      expect(report.passed, isTrue);
      expect(inferCalls, 1, reason: 'replay must not call inference again');
    });
  });
}
