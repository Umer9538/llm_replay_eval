import 'package:flutter_test/flutter_test.dart';
import 'package:llm_replay_eval/llm_replay_eval.dart';

void main() {
  group('parseJudgeVerdict', () {
    test('parses JSON with score, pass, and reason', () {
      final v = parseJudgeVerdict('{"score":0.9,"pass":true,"reason":"good"}');
      expect(v.score, 0.9);
      expect(v.passed, isTrue);
      expect(v.reason, 'good');
    });

    test('normalizes 0..10 and 0..100 score scales to 0..1', () {
      expect(parseJudgeVerdict('{"score":8}').score, closeTo(0.8, 1e-9));
      expect(parseJudgeVerdict('{"score":75}').score, closeTo(0.75, 1e-9));
    });

    test('honors explicit pass even with a low score', () {
      final v = parseJudgeVerdict('{"score":0.2,"pass":true}');
      expect(v.passed, isTrue);
    });

    test('uses threshold when only a score is present', () {
      expect(
        parseJudgeVerdict('{"score":0.6}', passThreshold: 0.7).passed,
        isFalse,
      );
      expect(
        parseJudgeVerdict('{"score":0.8}', passThreshold: 0.7).passed,
        isTrue,
      );
    });

    test('parses keyword verdicts', () {
      expect(parseJudgeVerdict('PASS — looks correct').passed, isTrue);
      expect(parseJudgeVerdict('FAIL: missing the point').passed, isFalse);
      expect(parseJudgeVerdict('Yes, this is correct.').passed, isTrue);
    });

    test('parses a bare leading number', () {
      expect(parseJudgeVerdict('0.85 because it is accurate').passed, isTrue);
    });

    test('fails closed on unparseable verdicts', () {
      final v = parseJudgeVerdict('the model rambled without a verdict here');
      expect(v.passed, isFalse);
      expect(v.score, 0.0);
    });

    test('extracts JSON embedded in surrounding prose', () {
      final v = parseJudgeVerdict(
        'Sure! Here is my grade: {"score":1.0,"pass":true} hope it helps',
      );
      expect(v.passed, isTrue);
      expect(v.score, 1.0);
    });
  });

  group('LlmJudge (cassetted)', () {
    test(
      'records the verdict once, then replays it deterministically',
      () async {
        var judgeCalls = 0;
        Future<String> judge(String prompt) async {
          judgeCalls++;
          return '{"score":0.95,"pass":true,"reason":"accurate"}';
        }

        // Record pass.
        final recSession = ReplaySession(
          cassette: Cassette('judge'),
          mode: ReplayMode.record,
        );
        final recJudge = LlmJudge(
          session: recSession,
          rubric: 'accurate?',
          judge: judge,
        );
        final r1 = await recJudge.evaluate(
          const EvalInput('The capital is Paris.'),
        );
        expect(r1.passed, isTrue);
        expect(r1.score, 0.95);
        expect(judgeCalls, 1);

        // Replay pass — judge model must NOT be called again.
        final replaySession = ReplaySession(
          cassette: recSession.cassette,
          mode: ReplayMode.replay,
        );
        final replayJudge = LlmJudge(
          session: replaySession,
          rubric: 'accurate?',
          judge: judge,
        );
        final r2 = await replayJudge.evaluate(
          const EvalInput('The capital is Paris.'),
        );
        expect(r2.passed, isTrue);
        expect(r2.score, 0.95);
        expect(
          judgeCalls,
          1,
          reason: 'verdict served from cassette, judge frozen',
        );
      },
    );

    test('replay miss surfaces a CassetteMissException', () async {
      final session = ReplaySession(
        cassette: Cassette('judge'),
        mode: ReplayMode.replay,
      );
      final judge = LlmJudge(
        session: session,
        rubric: 'ok?',
        judge: (_) async => 'PASS',
      );
      expect(
        () => judge.evaluate(const EvalInput('never recorded')),
        throwsA(isA<CassetteMissException>()),
      );
    });
  });
}
