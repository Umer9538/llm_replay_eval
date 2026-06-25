/// Controls whether interactions are served from a cassette or recorded live.
enum ReplayMode {
  /// Always call the real model and (over)write the cassette.
  /// The "re-record everything" mode — analogous to `--update-goldens`.
  record,

  /// Serve exclusively from the cassette. A cache miss is a hard failure.
  /// This is the correct mode for CI: tests must be hermetic and offline.
  replay,

  /// Serve from the cassette when present, otherwise record the miss.
  /// The convenient default for local development.
  auto,
}

/// Resolves the active [ReplayMode] from an environment value such as the
/// `LLM_REPLAY_MODE` dart-define / environment variable.
///
/// Accepts `record`, `replay`, `auto` (case-insensitive). Returns
/// [fallback] for null/empty/unrecognized input so a typo can't silently
/// switch a CI run into record mode.
ReplayMode replayModeFromString(
  String? value, {
  ReplayMode fallback = ReplayMode.auto,
}) {
  switch (value?.trim().toLowerCase()) {
    case 'record':
      return ReplayMode.record;
    case 'replay':
      return ReplayMode.replay;
    case 'auto':
      return ReplayMode.auto;
    default:
      return fallback;
  }
}

/// Thrown in [ReplayMode.replay] when a request has no recorded interaction.
///
/// The message is deliberately actionable: it tells the developer exactly how
/// to record the missing interaction rather than just reporting a cache miss.
class CassetteMissException implements Exception {
  CassetteMissException({
    required this.cassetteName,
    required this.key,
    this.request,
  });

  final String cassetteName;
  final String key;
  final Map<String, Object?>? request;

  @override
  String toString() {
    final reqLine = request == null ? '' : '\n  request: $request';
    return 'CassetteMissException: no recorded interaction in cassette '
        '"$cassetteName" for request $key.$reqLine\n'
        '  Run the recording step on a real device with '
        'LLM_REPLAY_MODE=record (or auto) to capture it, then commit the '
        'updated cassette.';
  }
}
