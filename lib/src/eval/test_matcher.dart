import 'package:flutter_test/flutter_test.dart';

import 'eval_result.dart';

/// Adapts any synchronous [Evaluator] into a `flutter_test` [Matcher], so eval
/// criteria can be used directly in `expect`:
///
/// ```dart
/// expect('Hello, world', satisfies(ContainsText('world')));
/// expect(EvalInput(output, meta: meta), satisfies(MaxTokens(64)));
/// ```
///
/// The matched value may be a [String] (wrapped as `EvalInput(value)`) or an
/// [EvalInput] directly. For asynchronous evaluators (e.g. `LlmJudge`), await
/// `evaluator.evaluate(...)` and assert on the returned [EvalResult] instead.
Matcher satisfies(Evaluator evaluator) => _EvaluatorMatcher(evaluator);

class _EvaluatorMatcher extends Matcher {
  _EvaluatorMatcher(this.evaluator);

  final Evaluator evaluator;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    final input = item is EvalInput ? item : EvalInput(item.toString());
    final result = evaluator.evaluate(input);
    if (result is Future) {
      throw ArgumentError(
        'satisfies() only supports synchronous evaluators. For async '
        'evaluators like LlmJudge, await evaluator.evaluate(...) and assert '
        'on the resulting EvalResult.',
      );
    }
    matchState['result'] = result;
    return result.passed;
  }

  @override
  Description describe(Description description) =>
      description.add('satisfies "${evaluator.name}"');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) {
    final result = matchState['result'] as EvalResult?;
    return mismatchDescription.add(
      result?.detail ?? 'did not satisfy "${evaluator.name}"',
    );
  }
}
