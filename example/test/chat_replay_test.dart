// Demonstrates the llm_replay_eval workflow end-to-end.
//
// By default this runs in REPLAY mode against the committed cassette at
// test/cassettes/faq.cassette.json — fast, offline, and deterministic, with the
// model never invoked. To refresh the cassette against the real model, run:
//
//   flutter test --dart-define=LLM_REPLAY_MODE=record
//
// (In a real project you'd record on a device/emulator where flutter_gemma can
// actually run; here the "model" is a canned stand-in so the example is
// self-contained.)

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_replay_eval/llm_replay_eval.dart';
import 'package:llm_replay_eval_example/on_device_llm.dart';

void main() {
  final mode = replayModeFromString(
    const String.fromEnvironment('LLM_REPLAY_MODE'),
    fallback: ReplayMode.replay,
  );

  ReplaySession openSession() => ReplaySession.open(
    name: 'faq',
    store: CassetteStore('test/cassettes'),
    mode: mode,
  );

  test('one-shot inference replays offline (model never runs)', () async {
    final llm = _SpyLlm(FakeGemma());
    final session = openSession();
    const prompt = 'Capital of France?';

    final reply = await session.run(
      request: {'prompt': prompt, 'model': llm.modelId, 'temperature': 0},
      live: () => llm.getResponse(prompt),
    );
    session.flush();

    expect(reply, contains('Paris'));
    if (mode == ReplayMode.replay) {
      expect(llm.calls, 0, reason: 'replay must not touch the model');
    }
  });

  test('streaming inference replays token chunks offline', () async {
    final llm = _SpyLlm(FakeGemma());
    final session = openSession();
    const prompt = 'Capital of France?';

    final chunks = await session
        .runStream(
          request: {'prompt': prompt, 'model': llm.modelId, 'stream': true},
          live: () => llm.getResponseAsync(prompt),
        )
        .toList();
    session.flush();

    expect(chunks.join(), contains('Paris'));
    if (mode == ReplayMode.replay) {
      expect(llm.streamCalls, 0, reason: 'replay must not touch the model');
    }
  });

  test(
    'eval suite scores replayed output with deterministic matchers',
    () async {
      final llm = _SpyLlm(FakeGemma());
      final session = openSession();

      final report = await EvalSuite('faq', [
        EvalCase(
          name: 'capital of France',
          request: {
            'prompt': 'Capital of France?',
            'model': llm.modelId,
            'temperature': 0,
          },
          infer: () => llm.getResponse('Capital of France?'),
          checks: [ContainsText('Paris'), MaxOutputLength(100)],
        ),
        EvalCase(
          name: 'returns valid fruit JSON',
          request: {'prompt': 'List 3 fruits as JSON', 'model': llm.modelId},
          infer: () => llm.getResponse('List 3 fruits as JSON'),
          checks: [
            IsValidJson(),
            JsonHasKeys(['fruits']),
          ],
        ),
      ]).run(session);

      expect(report.passed, isTrue, reason: report.summary());
      expect(report.passRate, 1.0);
    },
  );

  test('LLM-as-judge verdict is cassetted and replays offline', () async {
    final judgeModel = _SpyLlm(_FakeJudge());
    final session = openSession();

    final judge = LlmJudge(
      session: session,
      rubric: 'Does the answer correctly name Paris as the capital of France?',
      judge: (prompt) => judgeModel.getResponse(prompt),
    );

    final result = await judge.evaluate(
      const EvalInput('The capital of France is Paris.'),
    );
    session.flush();

    expect(result.passed, isTrue);
    if (mode == ReplayMode.replay) {
      expect(judgeModel.calls, 0, reason: 'judge verdict served from cassette');
    }
  });
}

/// Wraps an [OnDeviceLlm] and counts how often it is actually invoked, so the
/// tests can prove the real model is never touched during replay.
class _SpyLlm implements OnDeviceLlm {
  _SpyLlm(this._inner);
  final OnDeviceLlm _inner;
  int calls = 0;
  int streamCalls = 0;

  @override
  String get modelId => _inner.modelId;

  @override
  Future<String> getResponse(String prompt) {
    calls++;
    return _inner.getResponse(prompt);
  }

  @override
  Stream<String> getResponseAsync(String prompt) {
    streamCalls++;
    return _inner.getResponseAsync(prompt);
  }
}

/// A canned judge model that returns a structured verdict.
class _FakeJudge implements OnDeviceLlm {
  @override
  String get modelId => 'fake-judge';

  @override
  Future<String> getResponse(String prompt) async {
    await Future<void>.delayed(
      const Duration(milliseconds: 800),
    ); // judge model
    return '{"score": 0.95, "pass": true, "reason": "correctly identifies Paris"}';
  }

  @override
  Stream<String> getResponseAsync(String prompt) async* {
    yield await getResponse(prompt);
  }
}
