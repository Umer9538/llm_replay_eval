import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_replay_eval/llm_replay_eval.dart';

void main() {
  group('ReplaySession.run (one-shot)', () {
    test('record mode calls live and captures the result', () async {
      var calls = 0;
      final s = ReplaySession(cassette: Cassette('c'), mode: ReplayMode.record);
      final out = await s.run(
        request: {'prompt': 'hi'},
        live: () async {
          calls++;
          return 'live answer';
        },
      );
      expect(out, 'live answer');
      expect(calls, 1);
      expect(s.isDirty, isTrue);
      expect(s.cassette.match({'prompt': 'hi'})!.response.text, 'live answer');
    });

    test('replay hit returns recorded text and never calls live', () async {
      final s = ReplaySession(cassette: Cassette('c'), mode: ReplayMode.record);
      await s.run(request: {'prompt': 'hi'}, live: () async => 'recorded');

      final replay = ReplaySession(
        cassette: s.cassette,
        mode: ReplayMode.replay,
      );
      var calls = 0;
      final out = await replay.run(
        request: {'prompt': 'hi'},
        live: () async {
          calls++;
          return 'SHOULD NOT RUN';
        },
      );
      expect(out, 'recorded');
      expect(calls, 0);
    });

    test('replay miss throws an actionable CassetteMissException', () async {
      final s = ReplaySession(
        cassette: Cassette('chat'),
        mode: ReplayMode.replay,
      );
      expect(
        () => s.run(request: {'prompt': 'unseen'}, live: () async => 'x'),
        throwsA(isA<CassetteMissException>()),
      );
    });

    test('auto records on miss, then serves on the next call', () async {
      var calls = 0;
      final s = ReplaySession(cassette: Cassette('c'), mode: ReplayMode.auto);
      Future<String> live() async {
        calls++;
        return 'answer-$calls';
      }

      final first = await s.run(request: {'prompt': 'q'}, live: live);
      final second = await s.run(request: {'prompt': 'q'}, live: live);
      expect(first, 'answer-1');
      expect(second, 'answer-1', reason: 'second call replays the first');
      expect(calls, 1);
    });

    test('record mode re-runs live even when a recording exists', () async {
      final cassette = Cassette('c');
      final rec = ReplaySession(cassette: cassette, mode: ReplayMode.record);
      await rec.run(request: {'prompt': 'q'}, live: () async => 'old');

      var calls = 0;
      final out = await rec.run(
        request: {'prompt': 'q'},
        live: () async {
          calls++;
          return 'new';
        },
      );
      expect(out, 'new');
      expect(calls, 1);
      expect(cassette.match({'prompt': 'q'})!.response.text, 'new');
    });
  });

  group('ReplaySession.runStream (streaming)', () {
    Stream<String> source(List<String> toks, void Function() onStart) async* {
      onStart();
      for (final t in toks) {
        yield t;
      }
    }

    test('record captures chunks while passing them through', () async {
      var started = 0;
      final s = ReplaySession(cassette: Cassette('c'), mode: ReplayMode.record);
      final got = await s
          .runStream(
            request: {'prompt': 'hi'},
            live: () => source(['a', 'b', 'c'], () => started++),
          )
          .toList();
      expect(got, ['a', 'b', 'c']);
      expect(started, 1);
      final recorded = s.cassette.match({'prompt': 'hi'})!.response;
      expect(recorded.kind, ResponseKind.streaming);
      expect(recorded.text, 'abc');
    });

    test(
      'replay re-emits recorded chunks without touching the source',
      () async {
        final s = ReplaySession(
          cassette: Cassette('c'),
          mode: ReplayMode.record,
        );
        await s
            .runStream(
              request: {'prompt': 'hi'},
              live: () => source(['x', 'y'], () {}),
            )
            .toList();

        final replay = ReplaySession(
          cassette: s.cassette,
          mode: ReplayMode.replay,
        );
        var started = 0;
        final got = await replay
            .runStream(
              request: {'prompt': 'hi'},
              live: () => source(['NOPE'], () => started++),
            )
            .toList();
        expect(got, ['x', 'y']);
        expect(started, 0);
      },
    );

    test(
      'replay miss surfaces CassetteMissException through the stream',
      () async {
        final s = ReplaySession(
          cassette: Cassette('c'),
          mode: ReplayMode.replay,
        );
        expect(
          s.runStream(
            request: {'prompt': 'no'},
            live: () => source(['a'], () {}),
          ),
          emitsError(isA<CassetteMissException>()),
        );
      },
    );
  });

  group('ReplaySession persistence', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('rs_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('open() loads a previously saved cassette and replays it', () async {
      final store = CassetteStore(tmp.path);
      final recorder = ReplaySession.open(
        name: 'chat',
        store: store,
        mode: ReplayMode.record,
      );
      await recorder.run(request: {'prompt': 'hi'}, live: () async => 'saved');
      recorder.flush();

      // Fresh session, replay mode, loaded from disk.
      final replay = ReplaySession.open(
        name: 'chat',
        store: store,
        mode: ReplayMode.replay,
      );
      final out = await replay.run(
        request: {'prompt': 'hi'},
        live: () async => 'SHOULD NOT RUN',
      );
      expect(out, 'saved');
    });

    test('flush is a no-op when nothing was recorded', () {
      final store = CassetteStore(tmp.path);
      final s = ReplaySession.open(
        name: 'empty',
        store: store,
        mode: ReplayMode.replay,
      );
      s.flush();
      expect(store.exists('empty'), isFalse);
    });

    test(
      'cassettes are deterministic: re-recording yields identical bytes',
      () async {
        final store = CassetteStore(tmp.path);

        Future<void> record() async {
          final s = ReplaySession.open(
            name: 'det',
            store: store,
            mode: ReplayMode.record,
          );
          await s.run(
            request: {'prompt': 'hi', 'temp': 0},
            live: () async => 'r',
          );
          await s
              .runStream(
                request: {'prompt': 'stream'},
                live: () => Stream.fromIterable(['a', 'b']),
              )
              .toList();
          s.flush();
        }

        await record();
        final first = File(store.pathFor('det')).readAsStringSync();
        await record();
        final second = File(store.pathFor('det')).readAsStringSync();
        expect(
          second,
          equals(first),
          reason: 'no timestamps/timing by default → clean git diffs',
        );
      },
    );
  });
}
