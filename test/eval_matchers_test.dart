import 'package:flutter_test/flutter_test.dart';
import 'package:llm_replay_eval/llm_replay_eval.dart';

void main() {
  group('deterministic matchers', () {
    test('ContainsText respects case sensitivity', () {
      expect(
        ContainsText('World').evaluate(const EvalInput('Hello World')).passed,
        isTrue,
      );
      expect(
        ContainsText('world').evaluate(const EvalInput('Hello World')).passed,
        isFalse,
      );
      expect(
        ContainsText(
          'world',
          caseSensitive: false,
        ).evaluate(const EvalInput('Hello World')).passed,
        isTrue,
      );
    });

    test('MatchesPattern checks a regex', () {
      final m = MatchesPattern(RegExp(r'\d{3}-\d{4}'));
      expect(m.evaluate(const EvalInput('call 555-1234')).passed, isTrue);
      expect(m.evaluate(const EvalInput('no number')).passed, isFalse);
    });

    test('EqualsText trims by default', () {
      expect(
        EqualsText('hi').evaluate(const EvalInput('  hi  ')).passed,
        isTrue,
      );
      expect(
        EqualsText(
          'hi',
          trim: false,
        ).evaluate(const EvalInput('  hi  ')).passed,
        isFalse,
      );
    });

    test('IsValidJson accepts objects and arrays, rejects junk', () {
      expect(IsValidJson().evaluate(const EvalInput('{"a":1}')).passed, isTrue);
      expect(IsValidJson().evaluate(const EvalInput('[1,2]')).passed, isTrue);
      expect(
        IsValidJson().evaluate(const EvalInput('not json')).passed,
        isFalse,
      );
    });

    test('JsonHasKeys reports missing keys', () {
      final m = JsonHasKeys(['name', 'age']);
      expect(
        m.evaluate(const EvalInput('{"name":"x","age":1}')).passed,
        isTrue,
      );
      final miss = m.evaluate(const EvalInput('{"name":"x"}'));
      expect(miss.passed, isFalse);
      expect(miss.detail, contains('age'));
    });

    test('JsonFieldEquals walks dotted paths incl. list indices', () {
      expect(
        JsonFieldEquals(
          'usage.tokens',
          42,
        ).evaluate(const EvalInput('{"usage":{"tokens":42}}')).passed,
        isTrue,
      );
      expect(
        JsonFieldEquals(
          'choices.0.text',
          'hi',
        ).evaluate(const EvalInput('{"choices":[{"text":"hi"}]}')).passed,
        isTrue,
      );
      expect(
        JsonFieldEquals(
          'usage.tokens',
          99,
        ).evaluate(const EvalInput('{"usage":{"tokens":42}}')).passed,
        isFalse,
      );
    });

    test('MaxOutputLength bounds character count', () {
      expect(
        MaxOutputLength(5).evaluate(const EvalInput('hello')).passed,
        isTrue,
      );
      expect(
        MaxOutputLength(4).evaluate(const EvalInput('hello')).passed,
        isFalse,
      );
    });

    test('MaxTokens reads meta and fails closed when absent', () {
      expect(
        MaxTokens(
          10,
        ).evaluate(const EvalInput('x', meta: {'tokens': 8})).passed,
        isTrue,
      );
      expect(
        MaxTokens(
          10,
        ).evaluate(const EvalInput('x', meta: {'tokens': 20})).passed,
        isFalse,
      );
      expect(
        MaxTokens(10).evaluate(const EvalInput('x')).passed,
        isFalse,
        reason: 'no token count must not silently pass',
      );
    });
  });

  group('satisfies() flutter_test bridge', () {
    test('works inside expect for strings and EvalInput', () {
      expect(
        'Hello world',
        satisfies(ContainsText('world', caseSensitive: false)),
      );
      expect(
        const EvalInput('x', meta: {'tokens': 3}),
        satisfies(MaxTokens(5)),
      );
    });

    test('async evaluators are rejected with a helpful error', () {
      // Record mode so the detection probe completes cleanly (no replay miss).
      final session = ReplaySession(
        cassette: Cassette('j'),
        mode: ReplayMode.record,
      );
      final judge = LlmJudge(
        session: session,
        rubric: 'is it polite?',
        judge: (_) async => '{"pass":true}',
      );
      // Call matches() directly: expect() would swallow the throw into a
      // TestFailure, so we assert on the matcher API itself.
      expect(
        () => satisfies(judge).matches('hi', <Object?, Object?>{}),
        throwsArgumentError,
      );
    });
  });

  group('EvalResult', () {
    test('toString reflects pass/fail, score, and detail', () {
      expect(
        EvalResult.boolean('c', passed: true).toString(),
        contains('PASS'),
      );
      final scored = const EvalResult(
        criterion: 'c',
        passed: false,
        score: 0.25,
        detail: 'nope',
      );
      expect(scored.toString(), contains('25.0%'));
      expect(scored.toString(), contains('nope'));
    });
  });
}
