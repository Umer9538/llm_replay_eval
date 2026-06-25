import 'cassette.dart';
import 'cassette_store.dart';
import 'fingerprint.dart';
import 'replay_mode.dart';

/// Wraps real on-device inference calls with deterministic record/replay.
///
/// A [ReplaySession] is runtime-agnostic: it doesn't care whether the model is
/// flutter_gemma over a platform channel, llama_cpp_dart over FFI, or a custom
/// engine. You hand it the request (for fingerprinting) and a thunk that
/// performs the *real* inference; the session decides whether to call that thunk
/// or serve a previously recorded result.
///
/// Typical usage in a test:
/// ```dart
/// final session = ReplaySession.open(
///   name: 'chat',
///   store: CassetteStore('test/cassettes'),
///   // CI runs with replay; record on a device with LLM_REPLAY_MODE=record.
///   mode: replayModeFromString(
///     const String.fromEnvironment('LLM_REPLAY_MODE'),
///     fallback: ReplayMode.replay,
///   ),
/// );
///
/// final answer = await session.run(
///   request: {'prompt': prompt, 'model': 'gemma-2b', 'temperature': 0},
///   live: () => gemma.getResponse(prompt),
/// );
///
/// session.flush(); // persist any newly recorded interactions
/// ```
class ReplaySession {
  ReplaySession({
    required this.cassette,
    required this.mode,
    this.store,
    this.captureTiming = false,
  });

  /// Opens a session, loading an existing cassette named [name] from [store]
  /// if one is present (otherwise starting empty).
  factory ReplaySession.open({
    required String name,
    required ReplayMode mode,
    CassetteStore? store,
    bool captureTiming = false,
  }) {
    final cassette = store?.load(name) ?? Cassette(name);
    return ReplaySession(
      cassette: cassette,
      mode: mode,
      store: store,
      captureTiming: captureTiming,
    );
  }

  final Cassette cassette;
  final ReplayMode mode;

  /// Where cassettes are persisted. `null` keeps everything in memory.
  final CassetteStore? store;

  /// Whether to record inter-chunk timing for streaming responses. Off by
  /// default so re-recording an unchanged interaction yields a byte-identical
  /// cassette file — keeping git diffs meaningful. Turn on for demos that want
  /// to replay the model's real typing cadence.
  final bool captureTiming;

  bool _dirty = false;

  /// Whether there are unsaved recordings.
  bool get isDirty => _dirty;

  /// Runs a one-shot inference with record/replay applied.
  ///
  /// - replay/auto with a hit → returns the recorded text, [live] never runs.
  /// - [ReplayMode.replay] with a miss → throws [CassetteMissException].
  /// - record, or auto with a miss → runs [live] and records the result.
  Future<String> run({
    required Map<String, Object?> request,
    required Future<String> Function() live,
  }) async {
    final key = fingerprintRequest(request);
    final existing = cassette.find(key);

    if (mode != ReplayMode.record && existing != null) {
      return existing.response.text;
    }
    if (mode == ReplayMode.replay) {
      throw CassetteMissException(
        cassetteName: cassette.name,
        key: key,
        request: request,
      );
    }

    final text = await live();
    _record(key, request, RecordedResponse.oneShot(text));
    return text;
  }

  /// Runs a streaming inference with record/replay applied.
  ///
  /// On a hit, the recorded chunks are re-emitted (instantly, or honoring
  /// recorded timing when [captureTiming] was set). On a miss in
  /// [ReplayMode.replay] the returned stream emits a [CassetteMissException].
  /// Otherwise [live] is consumed and captured as it flows to the caller.
  Stream<String> runStream({
    required Map<String, Object?> request,
    required Stream<String> Function() live,
  }) {
    final key = fingerprintRequest(request);
    final existing = cassette.find(key);

    if (mode != ReplayMode.record && existing != null) {
      return _replay(existing.response);
    }
    if (mode == ReplayMode.replay) {
      return Stream<String>.error(
        CassetteMissException(
          cassetteName: cassette.name,
          key: key,
          request: request,
        ),
      );
    }
    return _recordStream(key, request, live());
  }

  Stream<String> _replay(RecordedResponse response) async* {
    for (final chunk in response.chunks) {
      if (captureTiming &&
          chunk.delayMicros != null &&
          chunk.delayMicros! > 0) {
        await Future<void>.delayed(Duration(microseconds: chunk.delayMicros!));
      }
      yield chunk.text;
    }
  }

  Stream<String> _recordStream(
    String key,
    Map<String, Object?> request,
    Stream<String> source,
  ) async* {
    final chunks = <RecordedChunk>[];
    final stopwatch = Stopwatch()..start();
    var last = 0;
    await for (final text in source) {
      final now = stopwatch.elapsedMicroseconds;
      chunks.add(
        RecordedChunk(text, delayMicros: captureTiming ? now - last : null),
      );
      last = now;
      yield text;
    }
    _record(key, request, RecordedResponse.streaming(chunks));
  }

  void _record(
    String key,
    Map<String, Object?> request,
    RecordedResponse response,
  ) {
    cassette.put(
      Interaction(
        key: key,
        // Store the canonical request so the cassette is debuggable in a diff.
        request: (canonicalize(request)! as Map).cast<String, Object?>(),
        response: response,
      ),
    );
    _dirty = true;
  }

  /// Persists the cassette to [store] if there are unsaved recordings.
  /// No-op when there is no store or nothing changed.
  void flush() {
    if (store != null && _dirty) {
      store!.save(cassette);
      _dirty = false;
    }
  }
}
