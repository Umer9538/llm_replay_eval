/// A stand-in for an on-device LLM runtime (flutter_gemma, cactus, …).
///
/// In a real app you'd replace this with `flutter_gemma`'s `InferenceModel`,
/// whose API has the same shape: a one-shot [getResponse] and a streaming
/// [getResponseAsync]. It's kept fake here so the example runs without
/// downloading a multi-gigabyte model — and so you can see what
/// `llm_replay_eval` does *around* a runtime, independent of which one you use.
abstract class OnDeviceLlm {
  String get modelId;
  Future<String> getResponse(String prompt);
  Stream<String> getResponseAsync(String prompt);
}

/// A canned implementation so the example is self-contained. Imagine these
/// answers coming from a real on-device Gemma model.
class FakeGemma implements OnDeviceLlm {
  @override
  String get modelId => 'fake-gemma-2b';

  @override
  Future<String> getResponse(String prompt) async {
    // Real on-device inference takes hundreds of ms+; this stand-in mimics that
    // so the record/replay speed difference is realistic. (The delay is never
    // recorded into the cassette — replays stay instant and deterministic.)
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return _answer(prompt);
  }

  @override
  Stream<String> getResponseAsync(String prompt) async* {
    for (final word in _answer(prompt).split(' ')) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      yield '$word ';
    }
  }

  String _answer(String prompt) {
    final p = prompt.toLowerCase();
    if (p.contains('capital') && p.contains('france')) {
      return 'The capital of France is Paris.';
    }
    if (p.contains('json') && p.contains('fruit')) {
      return '{"fruits": ["apple", "banana", "cherry"]}';
    }
    return 'I am a small on-device model and I am not sure about that.';
  }
}
