import 'dart:convert';

import '../replay_session.dart';
import 'eval_result.dart';

/// A parsed judge verdict: a 0..1 score, a pass flag, and a reason.
class JudgeVerdict {
  const JudgeVerdict({required this.score, required this.passed, this.reason});

  final double score;
  final bool passed;
  final String? reason;
}

/// Leniently parses a judge model's free-form reply into a [JudgeVerdict].
///
/// Real judges are inconsistent, so this tries several shapes in order:
///   1. JSON with `score` (0..1 or 0..10) and/or `pass`/`passed` and `reason`.
///   2. An explicit PASS/FAIL or YES/NO keyword.
///   3. A bare leading number (0..1 or 0..10).
/// If nothing is recognizable it fails closed (score 0, passed=false) so an
/// unparseable verdict never silently passes a test. [passThreshold] decides
/// pass/fail when only a score is present.
JudgeVerdict parseJudgeVerdict(String raw, {double passThreshold = 0.5}) {
  final text = raw.trim();

  // 1. JSON object somewhere in the reply.
  final jsonStart = text.indexOf('{');
  final jsonEnd = text.lastIndexOf('}');
  if (jsonStart != -1 && jsonEnd > jsonStart) {
    try {
      final obj = jsonDecode(text.substring(jsonStart, jsonEnd + 1));
      if (obj is Map) {
        final score = _normalizeScore(obj['score']);
        final reason = obj['reason']?.toString();
        final explicitPass = _asBool(obj['pass'] ?? obj['passed']);
        if (score != null || explicitPass != null) {
          final s = score ?? (explicitPass! ? 1.0 : 0.0);
          return JudgeVerdict(
            score: s,
            passed: explicitPass ?? (s >= passThreshold),
            reason: reason,
          );
        }
      }
    } on FormatException {
      // fall through to keyword parsing
    }
  }

  // 2. Keyword verdicts.
  final upper = text.toUpperCase();
  if (RegExp(r'\bPASS\b|\bYES\b|\bCORRECT\b').hasMatch(upper) &&
      !RegExp(r'\bFAIL\b|\bNO\b|\bINCORRECT\b').hasMatch(upper)) {
    return JudgeVerdict(score: 1.0, passed: true, reason: _firstLine(text));
  }
  if (RegExp(r'\bFAIL\b|\bNO\b|\bINCORRECT\b').hasMatch(upper)) {
    return JudgeVerdict(score: 0.0, passed: false, reason: _firstLine(text));
  }

  // 3. Bare leading number.
  final num = RegExp(r'-?\d+(\.\d+)?').firstMatch(text);
  if (num != null) {
    final score = _normalizeScore(double.tryParse(num.group(0)!));
    if (score != null) {
      return JudgeVerdict(
        score: score,
        passed: score >= passThreshold,
        reason: _firstLine(text),
      );
    }
  }

  // Fail closed.
  return JudgeVerdict(score: 0.0, passed: false, reason: 'unparseable verdict');
}

/// An [Evaluator] that asks a model to grade the output, with the judge call
/// routed through a [ReplaySession] so the verdict is recorded once and
/// replayed deterministically forever after — making LLM-as-judge evals
/// hermetic and offline in CI, which is the whole point.
class LlmJudge extends Evaluator {
  LlmJudge({
    required this.session,
    required this.rubric,
    required this.judge,
    this.passThreshold = 0.5,
    this.model = 'judge',
    String? name,
  }) : _name = name ?? 'llm judge';

  /// The session used for the judge call (record once, replay always).
  final ReplaySession session;

  /// The grading instruction, e.g. "Is the answer factually correct and polite?".
  final String rubric;

  /// The real judge-model call, invoked only on a cassette miss / record.
  final Future<String> Function(String judgePrompt) judge;

  final double passThreshold;
  final String model;
  final String _name;

  @override
  String get name => _name;

  /// Builds the prompt sent to the judge model.
  String buildPrompt(String output) =>
      '''
You are grading an AI assistant's output against a rubric.

RUBRIC: $rubric

OUTPUT TO GRADE:
"""
$output
"""

Respond with a JSON object: {"score": <0..1>, "pass": <true|false>, "reason": "<short>"}.''';

  @override
  Future<EvalResult> evaluate(EvalInput input) async {
    final prompt = buildPrompt(input.output);
    final verdictText = await session.run(
      request: {
        'role': 'judge',
        'model': model,
        'rubric': rubric,
        'output': input.output,
      },
      live: () => judge(prompt),
    );
    final verdict = parseJudgeVerdict(
      verdictText,
      passThreshold: passThreshold,
    );
    return EvalResult(
      criterion: name,
      passed: verdict.passed,
      score: verdict.score,
      detail: verdict.reason,
    );
  }
}

double? _normalizeScore(Object? raw) {
  final n = raw is num
      ? raw.toDouble()
      : double.tryParse(raw?.toString() ?? '');
  if (n == null) return null;
  if (n.isNaN) return null;
  // Accept 0..1 directly; map 0..10 and 0..100 scales down.
  if (n <= 1.0 && n >= 0.0) return n;
  if (n <= 10.0 && n > 1.0) return n / 10.0;
  if (n <= 100.0 && n > 10.0) return n / 100.0;
  return n.clamp(0.0, 1.0).toDouble();
}

bool? _asBool(Object? raw) {
  if (raw is bool) return raw;
  switch (raw?.toString().toLowerCase()) {
    case 'true':
    case 'yes':
    case 'pass':
      return true;
    case 'false':
    case 'no':
    case 'fail':
      return false;
    default:
      return null;
  }
}

String _firstLine(String s) {
  final line = s.split('\n').first.trim();
  return line.length <= 120 ? line : '${line.substring(0, 120)}…';
}
