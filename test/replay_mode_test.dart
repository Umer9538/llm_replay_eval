import 'package:flutter_test/flutter_test.dart';
import 'package:llm_replay_eval/llm_replay_eval.dart';

void main() {
  group('replayModeFromString', () {
    test('parses each mode case-insensitively', () {
      expect(replayModeFromString('record'), ReplayMode.record);
      expect(replayModeFromString('REPLAY'), ReplayMode.replay);
      expect(replayModeFromString(' Auto '), ReplayMode.auto);
    });

    test('falls back safely on null/empty/garbage', () {
      expect(replayModeFromString(null), ReplayMode.auto);
      expect(replayModeFromString(''), ReplayMode.auto);
      expect(replayModeFromString('recrod'), ReplayMode.auto);
    });

    test('a typo cannot silently switch CI into record mode', () {
      // CI passes replay as the fallback; a misspelled override stays replay.
      expect(
        replayModeFromString('reclay', fallback: ReplayMode.replay),
        ReplayMode.replay,
      );
    });
  });

  group('CassetteMissException', () {
    test('message is actionable and names the cassette and key', () {
      final e = CassetteMissException(
        cassetteName: 'chat',
        key: 'abc123',
        request: {'prompt': 'hi'},
      );
      final s = e.toString();
      expect(s, contains('chat'));
      expect(s, contains('abc123'));
      expect(s, contains('LLM_REPLAY_MODE=record'));
      expect(s, contains('prompt'));
    });
  });
}
