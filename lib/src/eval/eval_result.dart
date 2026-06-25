import 'dart:async';

/// The thing an [Evaluator] judges: a model's output plus any metadata recorded
/// alongside it (token counts, finish reason, etc.).
class EvalInput {
  const EvalInput(this.output, {this.meta = const {}});

  /// The full text the model produced.
  final String output;

  /// Metadata captured at record time (e.g. `{'tokens': 42}`).
  final Map<String, Object?> meta;
}

/// The verdict of one [Evaluator] on one [EvalInput].
class EvalResult {
  const EvalResult({
    required this.criterion,
    required this.passed,
    this.score = double.nan,
    this.detail,
  });

  /// Convenience for a boolean pass/fail with score 1.0/0.0.
  factory EvalResult.boolean(
    String criterion, {
    required bool passed,
    String? detail,
  }) => EvalResult(
    criterion: criterion,
    passed: passed,
    score: passed ? 1.0 : 0.0,
    detail: detail,
  );

  /// The name of the check that produced this result.
  final String criterion;

  /// Whether the output satisfied the criterion.
  final bool passed;

  /// A 0..1 quality score where meaningful (e.g. a judge's rating).
  /// `NaN` when the check is purely boolean.
  final double score;

  /// Human-readable explanation, especially useful on failure.
  final String? detail;

  bool get hasScore => !score.isNaN;

  @override
  String toString() {
    final mark = passed ? 'PASS' : 'FAIL';
    final scoreStr = hasScore ? ' (${(score * 100).toStringAsFixed(1)}%)' : '';
    final detailStr = detail == null ? '' : ' — $detail';
    return '$mark $criterion$scoreStr$detailStr';
  }
}

/// Judges a model output against a single criterion.
///
/// Implementations may be deterministic (string/JSON checks) or themselves
/// call a model (see `LlmJudge`). [evaluate] may be sync or async.
abstract class Evaluator {
  String get name;
  FutureOr<EvalResult> evaluate(EvalInput input);
}
