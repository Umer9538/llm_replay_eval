import '../fingerprint.dart';
import '../replay_session.dart';
import 'eval_result.dart';

/// One row of an eval dataset: a request, how to produce its output, and the
/// checks the output must satisfy.
class EvalCase {
  EvalCase({
    required this.name,
    required this.request,
    required this.infer,
    required this.checks,
  });

  /// Human-readable case name (shown in the report).
  final String name;

  /// The request used for cassette fingerprinting.
  final Map<String, Object?> request;

  /// The real inference call, invoked only on a cassette miss / record.
  final Future<String> Function() infer;

  /// The evaluators this case's output must pass.
  final List<Evaluator> checks;
}

/// The evaluated outcome of one [EvalCase].
class CaseResult {
  CaseResult({required this.name, required this.output, required this.results});

  final String name;
  final String output;
  final List<EvalResult> results;

  /// A case passes only when every check passed.
  bool get passed => results.every((r) => r.passed);

  Map<String, Object?> toJson() => {
    'name': name,
    'passed': passed,
    'checks': [
      for (final r in results)
        {
          'criterion': r.criterion,
          'passed': r.passed,
          if (r.hasScore) 'score': r.score,
          if (r.detail != null) 'detail': r.detail,
        },
    ],
  };
}

/// The aggregate result of running an [EvalSuite].
class EvalReport {
  EvalReport(this.suiteName, this.cases);

  final String suiteName;
  final List<CaseResult> cases;

  int get total => cases.length;
  int get passedCount => cases.where((c) => c.passed).length;

  /// Fraction of cases that passed every check (0..1).
  double get passRate => total == 0 ? 1.0 : passedCount / total;

  /// Whether every case passed.
  bool get passed => passedCount == total;

  Map<String, Object?> toJson() => {
    'suite': suiteName,
    'total': total,
    'passed': passedCount,
    'passRate': passRate,
    'cases': cases.map((c) => c.toJson()).toList(),
  };

  /// A compact, readable summary suitable for printing to the console.
  String summary() {
    final buffer = StringBuffer()
      ..writeln(
        'Eval "$suiteName": $passedCount/$total passed '
        '(${(passRate * 100).toStringAsFixed(1)}%)',
      );
    for (final c in cases) {
      buffer.writeln('  ${c.passed ? "✓" : "✗"} ${c.name}');
      for (final r in c.results.where((r) => !r.passed)) {
        buffer.writeln('      ✗ $r');
      }
    }
    return buffer.toString().trimRight();
  }
}

/// A dataset of [EvalCase]s run against a [ReplaySession].
///
/// Because outputs flow through the session, the whole suite is deterministic
/// and offline in replay mode — including any [LlmJudge] checks, whose verdicts
/// are themselves cassetted.
class EvalSuite {
  EvalSuite(this.name, this.cases);

  final String name;
  final List<EvalCase> cases;

  Future<EvalReport> run(ReplaySession session) async {
    final results = <CaseResult>[];
    for (final c in cases) {
      final output = await session.run(request: c.request, live: c.infer);
      final meta =
          session.cassette.find(fingerprintRequest(c.request))?.response.meta ??
          const <String, Object?>{};
      final input = EvalInput(output, meta: meta);
      final checkResults = [
        for (final check in c.checks) await check.evaluate(input),
      ];
      results.add(
        CaseResult(name: c.name, output: output, results: checkResults),
      );
    }
    session.flush();
    return EvalReport(name, results);
  }
}
