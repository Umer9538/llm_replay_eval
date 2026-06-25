// FEASIBILITY SPIKE for llm_replay_eval.
//
// Make-or-break question: can we deterministically RECORD and REPLAY on-device
// LLM inference — the thing HTTP VCRs physically cannot touch because in-process
// models never hit the network?
//
// This spike proves the four load-bearing mechanisms with ZERO production code,
// using only flutter_test. If these pass, the moat is real and buildable:
//
//   A. Streaming record/replay round-trips token chunks byte-identically, and
//      replay NEVER invokes the (expensive, non-deterministic) real model.
//   B. A cassette survives JSON serialization and replays from disk-shaped data.
//   C. Request fingerprinting is canonical: same request (even with keys in a
//      different order) -> same key (hit); different request -> different key (miss).
//   D. We can transparently intercept a flutter_gemma-style platform-channel call
//      inside `flutter test` and serve a recorded response, with the native side
//      never running. (The zero-config "you change no code" path.)

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// --- Minimal stand-ins for what the real package will provide -----------------

/// Canonical, order-independent JSON encoding so that two semantically-equal
/// requests hash to the same fingerprint regardless of key order.
Object? _canonicalize(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canonicalize(v[k])};
  }
  if (v is List) return v.map(_canonicalize).toList();
  return v;
}

/// Stable 64-bit FNV-1a hash (pure Dart, no crypto dep) over canonical JSON.
/// The real package will swap in sha256, but this proves determinism.
String fingerprint(Map<String, Object?> request) {
  final canonical = jsonEncode(_canonicalize(request));
  var hash = 0xcbf29ce484222325;
  for (final unit in utf8.encode(canonical)) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// One recorded interaction: a request fingerprint -> ordered streamed chunks.
class CassetteEntry {
  CassetteEntry(this.key, this.chunks);
  final String key;
  final List<String> chunks;

  Map<String, Object?> toJson() => {'key': key, 'chunks': chunks};
  static CassetteEntry fromJson(Map<String, Object?> j) =>
      CassetteEntry(j['key']! as String, (j['chunks']! as List).cast<String>());
}

/// In-memory cassette: record wraps a real stream and captures it; replay
/// reconstructs the stream from captured chunks without touching the source.
class Cassette {
  final Map<String, CassetteEntry> _entries = {};

  bool has(String key) => _entries.containsKey(key);

  Stream<String> record(String key, Stream<String> source) async* {
    final chunks = <String>[];
    await for (final chunk in source) {
      chunks.add(chunk);
      yield chunk; // pass-through while recording
    }
    _entries[key] = CassetteEntry(key, chunks);
  }

  Stream<String> replay(String key) async* {
    final entry = _entries[key];
    if (entry == null) {
      throw StateError('cassette miss for $key — record it first');
    }
    for (final chunk in entry.chunks) {
      yield chunk;
    }
  }

  String toJsonString() => jsonEncode({
    'version': 1,
    'entries': _entries.values.map((e) => e.toJson()).toList(),
  });

  static Cassette fromJsonString(String s) {
    final root = jsonDecode(s) as Map<String, Object?>;
    final c = Cassette();
    for (final e in (root['entries']! as List).cast<Map<String, Object?>>()) {
      final entry = CassetteEntry.fromJson(e);
      c._entries[entry.key] = entry;
    }
    return c;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'SPIKE A — streaming record/replay is deterministic and source-free',
    () {
      test(
        'replay reproduces chunks byte-for-byte and never calls the model',
        () async {
          var realInvocations = 0;

          // Simulates flutter_gemma's InferenceModel streaming API:
          //   Stream<String> generateResponseAsync(prompt)
          Stream<String> fakeOnDeviceModel(String prompt) async* {
            realInvocations++;
            for (final tok in const ['The ', 'quick ', 'brown ', 'fox']) {
              yield tok;
            }
          }

          final cassette = Cassette();
          const key = 'k1';

          // RECORD pass — drives the real model once, captures the stream.
          final recorded = await cassette
              .record(key, fakeOnDeviceModel('hi'))
              .toList();
          expect(recorded, ['The ', 'quick ', 'brown ', 'fox']);
          expect(realInvocations, 1);

          // REPLAY pass — must reproduce identically WITHOUT touching the model.
          final replayed = await cassette.replay(key).toList();
          expect(
            replayed,
            recorded,
            reason: 'replay must be byte-identical to record',
          );
          expect(
            realInvocations,
            1,
            reason: 'the real model must NOT run on replay',
          );

          // A second replay is just as deterministic.
          final replayedAgain = await cassette.replay(key).toList();
          expect(replayedAgain, recorded);
          expect(realInvocations, 1);
        },
      );

      test(
        'replay on a never-recorded request is a clear miss, not a silent pass',
        () {
          final cassette = Cassette();
          expect(cassette.replay('never').toList(), throwsStateError);
        },
      );
    },
  );

  group(
    'SPIKE B — cassettes survive serialization (record on device, replay in CI)',
    () {
      test(
        'a cassette serialized to JSON replays identically after reload',
        () async {
          final original = Cassette();
          await original
              .record('k', Stream.fromIterable(['a', 'b', 'c']))
              .toList();

          final onDisk = original
              .toJsonString(); // what would be committed to the repo
          final reloaded = Cassette.fromJsonString(onDisk);

          expect(reloaded.has('k'), isTrue);
          expect(await reloaded.replay('k').toList(), ['a', 'b', 'c']);
        },
      );
    },
  );

  group('SPIKE C — request fingerprinting is canonical and discriminating', () {
    test(
      'same request hits regardless of key order; different request misses',
      () {
        final a = fingerprint({
          'prompt': 'summarize this',
          'params': {'temperature': 0.0, 'topK': 40},
          'model': 'gemma-2b',
        });
        // Same values, keys in a different order — must collide (cache hit).
        final b = fingerprint({
          'model': 'gemma-2b',
          'params': {'topK': 40, 'temperature': 0.0},
          'prompt': 'summarize this',
        });
        // A meaningfully different request — must NOT collide (cache miss).
        final c = fingerprint({
          'prompt': 'summarize this',
          'params': {'temperature': 0.7, 'topK': 40},
          'model': 'gemma-2b',
        });

        expect(
          a,
          equals(b),
          reason: 'canonical fingerprint is key-order independent',
        );
        expect(
          a,
          isNot(equals(c)),
          reason: 'a changed param must change the key',
        );
        expect(a, hasLength(16));
      },
    );
  });

  group('SPIKE D — transparent platform-channel interception in flutter test', () {
    // This is the zero-config path: flutter_gemma talks to native MediaPipe over
    // a MethodChannel. We register a mock handler on that exact channel, so a
    // recorded response is served and the native side is never reached.
    const channel = MethodChannel(
      'flutter_gemma',
    ); // representative; pinned in M3
    final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test(
      'intercepts invokeMethod, serves cassette, native never runs',
      () async {
        var nativeReached = false;
        final cassette = <String, Object?>{};

        // Pretend a prior on-device recording produced this:
        final recordKey = fingerprint({
          'm': 'generateResponse',
          'prompt': 'hi',
        });
        cassette[recordKey] = 'Hello from the recorded model.';

        // What `installReplay()` will do under the hood:
        messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
          final key = fingerprint({
            'm': call.method,
            ...((call.arguments as Map?)?.cast<String, Object?>() ?? {}),
          });
          if (cassette.containsKey(key)) {
            return cassette[key]; // REPLAY hit — short-circuit native entirely
          }
          nativeReached = true; // in record mode we'd dispatch to native here
          return null;
        });

        // Simulates exactly what flutter_gemma does internally:
        final result = await channel.invokeMethod<String>('generateResponse', {
          'prompt': 'hi',
        });

        expect(result, 'Hello from the recorded model.');
        expect(
          nativeReached,
          isFalse,
          reason: 'a cassette hit must NOT reach the native model',
        );
      },
    );

    test(
      'a cassette miss falls through to the (recordable) native dispatch',
      () async {
        var nativeReached = false;
        final cassette = <String, Object?>{}; // empty: nothing recorded yet

        messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
          final key = fingerprint({'m': call.method});
          if (cassette.containsKey(key)) return cassette[key];
          nativeReached =
              true; // record mode would capture the real result here
          return 'live';
        });

        final result = await channel.invokeMethod<String>('generateResponse');
        expect(result, 'live');
        expect(
          nativeReached,
          isTrue,
          reason: 'misses must reach native so record mode can capture them',
        );
      },
    );
  });
}
