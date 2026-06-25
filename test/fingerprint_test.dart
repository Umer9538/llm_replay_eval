import 'package:flutter_test/flutter_test.dart';
import 'package:llm_replay_eval/llm_replay_eval.dart';

void main() {
  group('fingerprintRequest', () {
    test('is independent of map key order', () {
      final a = fingerprintRequest({
        'prompt': 'hello',
        'params': {'temperature': 0.0, 'topK': 40},
      });
      final b = fingerprintRequest({
        'params': {'topK': 40, 'temperature': 0.0},
        'prompt': 'hello',
      });
      expect(a, equals(b));
    });

    test('changes when any value changes', () {
      final base = fingerprintRequest({'prompt': 'hello', 'temp': 0.0});
      expect(
        fingerprintRequest({'prompt': 'hello', 'temp': 0.7}),
        isNot(equals(base)),
      );
      expect(
        fingerprintRequest({'prompt': 'world', 'temp': 0.0}),
        isNot(equals(base)),
      );
    });

    test('is a 64-char hex sha256 digest', () {
      final fp = fingerprintRequest({'prompt': 'x'});
      expect(fp, hasLength(64));
      expect(fp, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('is stable across calls (no time/random component)', () {
      final r = {'prompt': 'deterministic'};
      expect(fingerprintRequest(r), equals(fingerprintRequest(r)));
    });
  });

  group('digestBytes', () {
    test('reduces binary payloads to a stable short key', () {
      final bytes = List<int>.generate(4096, (i) => i % 256);
      final d1 = digestBytes(bytes);
      final d2 = digestBytes(List<int>.from(bytes));
      expect(d1, equals(d2));
      expect(d1, hasLength(64));
      expect(digestBytes([...bytes, 1]), isNot(equals(d1)));
    });

    test(
      'lets a multimodal request fingerprint without inlining the bytes',
      () {
        final image = List<int>.filled(1000000, 7);
        final fp = fingerprintRequest({
          'prompt': 'describe',
          'image': digestBytes(image),
        });
        expect(fp, hasLength(64));
      },
    );
  });

  group('canonicalize', () {
    test('sorts nested map keys and preserves list order', () {
      final c =
          canonicalize({
                'b': 1,
                'a': {
                  'z': [3, 1, 2],
                  'y': 2,
                },
              })
              as Map<String, Object?>;
      expect(c.keys.toList(), ['a', 'b']);
      final inner = c['a']! as Map<String, Object?>;
      expect(inner.keys.toList(), ['y', 'z']);
      expect(inner['z'], [3, 1, 2]); // list order is significant, untouched
    });
  });
}
