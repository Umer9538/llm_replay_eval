import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_replay_eval/llm_replay_eval.dart';

void main() {
  late Directory tmp;
  late CassetteStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('llm_replay_store_test');
    store = CassetteStore(tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Cassette demo() => Cassette('chat')
    ..put(
      Interaction(
        key: fingerprintRequest({'prompt': 'hi'}),
        request: {'prompt': 'hi'},
        response: RecordedResponse.streaming(const [
          RecordedChunk('Hel'),
          RecordedChunk('lo'),
        ]),
      ),
    );

  test('load() returns an empty cassette when no file exists', () {
    final c = store.load('missing');
    expect(c.isEmpty, isTrue);
    expect(c.name, 'missing');
  });

  test('save() then load() round-trips the cassette', () {
    store.save(demo());
    final loaded = store.load('chat');
    expect(loaded.length, 1);
    expect(loaded.match({'prompt': 'hi'})!.response.text, 'Hello');
  });

  test('save() creates the directory if it does not exist', () {
    final nested = CassetteStore('${tmp.path}/a/b/c');
    nested.save(demo());
    expect(nested.exists('chat'), isTrue);
    expect(File(nested.pathFor('chat')).existsSync(), isTrue);
  });

  test('cassette files are human-readable pretty JSON for clean diffs', () {
    store.save(demo());
    final text = File(store.pathFor('chat')).readAsStringSync();
    expect(text, contains('\n  ')); // indented
    expect(text, contains('"prompt": "hi"'));
    expect(text.endsWith('\n'), isTrue); // trailing newline for git
  });

  test('corrupt (non-object) cassette JSON throws a clear error', () {
    File(store.pathFor('bad')).writeAsStringSync('[1, 2, 3]');
    expect(() => store.load('bad'), throwsA(isA<CassetteFormatException>()));
  });
}
