import 'package:flutter_test/flutter_test.dart';
import 'package:llm_replay_eval/llm_replay_eval.dart';

void main() {
  Interaction sampleStreaming() => Interaction(
    key: fingerprintRequest({'prompt': 'hi'}),
    request: {'prompt': 'hi'},
    response: RecordedResponse.streaming(
      const [RecordedChunk('Hel'), RecordedChunk('lo', delayMicros: 1200)],
      meta: {'finishReason': 'stop', 'tokens': 2},
    ),
    recordedAt: '2026-06-25T00:00:00Z',
  );

  group('RecordedResponse', () {
    test('oneShot concatenates to its single chunk text', () {
      final r = RecordedResponse.oneShot('full answer');
      expect(r.kind, ResponseKind.oneShot);
      expect(r.text, 'full answer');
      expect(r.chunks, hasLength(1));
    });

    test('streaming text joins all chunks in order', () {
      final r = RecordedResponse.streaming(const [
        RecordedChunk('a'),
        RecordedChunk('b'),
        RecordedChunk('c'),
      ]);
      expect(r.text, 'abc');
    });

    test('round-trips through JSON including timing and meta', () {
      final r = RecordedResponse.streaming(
        const [RecordedChunk('x', delayMicros: 50)],
        meta: {'tokens': 1},
      );
      final back = RecordedResponse.fromJson(r.toJson());
      expect(back.kind, ResponseKind.streaming);
      expect(back.chunks.single.text, 'x');
      expect(back.chunks.single.delayMicros, 50);
      expect(back.meta['tokens'], 1);
    });

    test('omits empty meta from JSON', () {
      final json = RecordedResponse.oneShot('a').toJson();
      expect(json.containsKey('meta'), isFalse);
    });
  });

  group('Cassette', () {
    test('match() finds an interaction by fingerprinting the request', () {
      final c = Cassette('demo')..put(sampleStreaming());
      final hit = c.match({'prompt': 'hi'});
      expect(hit, isNotNull);
      expect(hit!.response.text, 'Hello');
      expect(c.match({'prompt': 'different'}), isNull);
    });

    test('put overwrites an interaction with the same key', () {
      final key = fingerprintRequest({'prompt': 'q'});
      final c = Cassette('demo')
        ..put(
          Interaction(
            key: key,
            request: {'prompt': 'q'},
            response: RecordedResponse.oneShot('v1'),
          ),
        )
        ..put(
          Interaction(
            key: key,
            request: {'prompt': 'q'},
            response: RecordedResponse.oneShot('v2'),
          ),
        );
      expect(c.length, 1);
      expect(c.find(key)!.response.text, 'v2');
    });

    test('remove deletes a present interaction and reports absence', () {
      final i = sampleStreaming();
      final c = Cassette('demo')..put(i);
      expect(c.remove(i.key), isTrue);
      expect(c.remove(i.key), isFalse);
      expect(c.isEmpty, isTrue);
    });

    test('round-trips through JSON with version and name preserved', () {
      final c = Cassette('demo')..put(sampleStreaming());
      final back = Cassette.fromJson(c.toJson());
      expect(back.name, 'demo');
      expect(back.length, 1);
      final i = back.interactions.single;
      expect(i.request['prompt'], 'hi');
      expect(i.response.text, 'Hello');
      expect(i.response.chunks[1].delayMicros, 1200);
      expect(i.recordedAt, '2026-06-25T00:00:00Z');
    });

    test('toJson stamps the current format version', () {
      expect(Cassette('x').toJson()['version'], Cassette.formatVersion);
    });

    test('rejects a cassette written by a newer format version', () {
      final tooNew = {
        'version': Cassette.formatVersion + 1,
        'name': 'future',
        'interactions': <Object?>[],
      };
      expect(
        () => Cassette.fromJson(tooNew),
        throwsA(isA<CassetteFormatException>()),
      );
    });

    test('tolerates a legacy cassette with no version field', () {
      final legacy = {'name': 'old', 'interactions': <Object?>[]};
      expect(Cassette.fromJson(legacy).name, 'old');
    });
  });
}
