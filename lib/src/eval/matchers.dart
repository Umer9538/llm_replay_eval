import 'dart:convert';

import 'eval_result.dart';

/// Passes when the output contains [substring].
class ContainsText extends Evaluator {
  ContainsText(this.substring, {this.caseSensitive = true});
  final String substring;
  final bool caseSensitive;

  @override
  String get name => 'contains "$substring"';

  @override
  EvalResult evaluate(EvalInput input) {
    final hay = caseSensitive ? input.output : input.output.toLowerCase();
    final needle = caseSensitive ? substring : substring.toLowerCase();
    final passed = hay.contains(needle);
    return EvalResult.boolean(
      name,
      passed: passed,
      detail: passed ? null : 'substring not found',
    );
  }
}

/// Passes when the output matches [pattern] anywhere.
class MatchesPattern extends Evaluator {
  MatchesPattern(this.pattern);
  final RegExp pattern;

  @override
  String get name => 'matches /${pattern.pattern}/';

  @override
  EvalResult evaluate(EvalInput input) {
    final passed = pattern.hasMatch(input.output);
    return EvalResult.boolean(
      name,
      passed: passed,
      detail: passed ? null : 'no match',
    );
  }
}

/// Passes when the output equals [expected] (optionally trimming whitespace).
class EqualsText extends Evaluator {
  EqualsText(this.expected, {this.trim = true});
  final String expected;
  final bool trim;

  @override
  String get name => 'equals expected';

  @override
  EvalResult evaluate(EvalInput input) {
    final a = trim ? input.output.trim() : input.output;
    final b = trim ? expected.trim() : expected;
    return EvalResult.boolean(
      name,
      passed: a == b,
      detail: a == b ? null : 'got "${_clip(a)}"',
    );
  }
}

/// Passes when the output parses as JSON (object or array).
class IsValidJson extends Evaluator {
  @override
  String get name => 'is valid JSON';

  @override
  EvalResult evaluate(EvalInput input) {
    try {
      jsonDecode(input.output);
      return EvalResult.boolean(name, passed: true);
    } on FormatException catch (e) {
      return EvalResult.boolean(name, passed: false, detail: e.message);
    }
  }
}

/// Passes when the output is a JSON object containing all of [keys].
class JsonHasKeys extends Evaluator {
  JsonHasKeys(this.keys);
  final List<String> keys;

  @override
  String get name => 'JSON has keys ${keys.join(", ")}';

  @override
  EvalResult evaluate(EvalInput input) {
    final Object? decoded;
    try {
      decoded = jsonDecode(input.output);
    } on FormatException {
      return EvalResult.boolean(name, passed: false, detail: 'not valid JSON');
    }
    if (decoded is! Map) {
      return EvalResult.boolean(
        name,
        passed: false,
        detail: 'JSON is not an object',
      );
    }
    final map = decoded; // promote out of closure capture
    final missing = keys.where((k) => !map.containsKey(k)).toList();
    return EvalResult.boolean(
      name,
      passed: missing.isEmpty,
      detail: missing.isEmpty ? null : 'missing: ${missing.join(", ")}',
    );
  }
}

/// Passes when a dotted [path] in the output JSON equals [value].
/// Example path: `usage.tokens` or `choices.0.text`.
class JsonFieldEquals extends Evaluator {
  JsonFieldEquals(this.path, this.value);
  final String path;
  final Object? value;

  @override
  String get name => 'JSON $path == $value';

  @override
  EvalResult evaluate(EvalInput input) {
    final Object? decoded;
    try {
      decoded = jsonDecode(input.output);
    } on FormatException {
      return EvalResult.boolean(name, passed: false, detail: 'not valid JSON');
    }
    Object? cursor = decoded;
    for (final segment in path.split('.')) {
      if (cursor is Map && cursor.containsKey(segment)) {
        cursor = cursor[segment];
      } else if (cursor is List) {
        final idx = int.tryParse(segment);
        if (idx == null || idx < 0 || idx >= cursor.length) {
          return EvalResult.boolean(
            name,
            passed: false,
            detail: 'path "$path" not found',
          );
        }
        cursor = cursor[idx];
      } else {
        return EvalResult.boolean(
          name,
          passed: false,
          detail: 'path "$path" not found',
        );
      }
    }
    return EvalResult.boolean(
      name,
      passed: cursor == value,
      detail: cursor == value ? null : 'got $cursor',
    );
  }
}

/// Passes when the output length is within [maxChars] characters.
class MaxOutputLength extends Evaluator {
  MaxOutputLength(this.maxChars);
  final int maxChars;

  @override
  String get name => 'length <= $maxChars chars';

  @override
  EvalResult evaluate(EvalInput input) {
    final len = input.output.length;
    return EvalResult.boolean(
      name,
      passed: len <= maxChars,
      detail: len <= maxChars ? null : 'was $len',
    );
  }
}

/// Passes when `meta['tokens']` is within [maxTokens]. A missing token count
/// is treated as a failure so a budget can't silently pass un-instrumented runs.
class MaxTokens extends Evaluator {
  MaxTokens(this.maxTokens);
  final int maxTokens;

  @override
  String get name => 'tokens <= $maxTokens';

  @override
  EvalResult evaluate(EvalInput input) {
    final tokens = (input.meta['tokens'] as num?)?.toInt();
    if (tokens == null) {
      return EvalResult.boolean(
        name,
        passed: false,
        detail: 'no token count in meta',
      );
    }
    return EvalResult.boolean(
      name,
      passed: tokens <= maxTokens,
      detail: tokens <= maxTokens ? null : 'was $tokens',
    );
  }
}

String _clip(String s, [int max = 60]) =>
    s.length <= max ? s : '${s.substring(0, max)}…';
