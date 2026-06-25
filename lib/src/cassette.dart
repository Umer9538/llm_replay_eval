import 'fingerprint.dart';

/// Whether a recorded response arrived all at once or token-by-token.
enum ResponseKind {
  /// A single, complete response (e.g. `getResponse(prompt)`).
  oneShot,

  /// An ordered stream of chunks (e.g. `getResponseAsync(prompt)`).
  streaming,
}

/// One streamed piece of a response, with the (optional) delay observed before
/// it arrived. Recording the timing lets replay optionally reproduce the
/// real cadence of on-device generation instead of dumping everything at once.
class RecordedChunk {
  const RecordedChunk(this.text, {this.delayMicros});

  final String text;

  /// Microseconds observed between the previous chunk and this one during
  /// recording. `null` means timing was not captured.
  final int? delayMicros;

  Map<String, Object?> toJson() => {
    'text': text,
    if (delayMicros != null) 'delayMicros': delayMicros,
  };

  static RecordedChunk fromJson(Map<String, Object?> json) => RecordedChunk(
    json['text']! as String,
    delayMicros: (json['delayMicros'] as num?)?.toInt(),
  );
}

/// The recorded output of one inference call.
class RecordedResponse {
  RecordedResponse({
    required this.kind,
    required this.chunks,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  /// A one-shot response from a single string.
  factory RecordedResponse.oneShot(String text, {Map<String, Object?>? meta}) =>
      RecordedResponse(
        kind: ResponseKind.oneShot,
        chunks: [RecordedChunk(text)],
        meta: meta,
      );

  /// A streaming response from ordered chunks.
  factory RecordedResponse.streaming(
    List<RecordedChunk> chunks, {
    Map<String, Object?>? meta,
  }) => RecordedResponse(
    kind: ResponseKind.streaming,
    chunks: chunks,
    meta: meta,
  );

  final ResponseKind kind;
  final List<RecordedChunk> chunks;

  /// Free-form metadata captured at record time (token counts, finishReason,
  /// total latency, model build id, …). Kept open for forward-compatibility.
  final Map<String, Object?> meta;

  /// The full response text, concatenating all chunks.
  String get text => chunks.map((c) => c.text).join();

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'chunks': chunks.map((c) => c.toJson()).toList(),
    if (meta.isNotEmpty) 'meta': meta,
  };

  static RecordedResponse fromJson(Map<String, Object?> json) =>
      RecordedResponse(
        kind: ResponseKind.values.byName(json['kind']! as String),
        chunks: (json['chunks']! as List)
            .cast<Map<String, Object?>>()
            .map(RecordedChunk.fromJson)
            .toList(),
        meta: (json['meta'] as Map?)?.cast<String, Object?>() ?? const {},
      );
}

/// One recorded request→response pair.
class Interaction {
  Interaction({
    required this.key,
    required this.request,
    required this.response,
    this.recordedAt,
  });

  /// The request fingerprint (see [fingerprintRequest]).
  final String key;

  /// A canonical, human-readable copy of the request that produced [key].
  /// Stored so cassette files are debuggable in a diff, not just opaque hashes.
  final Map<String, Object?> request;

  final RecordedResponse response;

  /// ISO-8601 timestamp of when this was recorded, if captured.
  final String? recordedAt;

  Map<String, Object?> toJson() => {
    'key': key,
    'request': request,
    'response': response.toJson(),
    if (recordedAt != null) 'recordedAt': recordedAt,
  };

  static Interaction fromJson(Map<String, Object?> json) => Interaction(
    key: json['key']! as String,
    request: (json['request'] as Map?)?.cast<String, Object?>() ?? const {},
    response: RecordedResponse.fromJson(
      json['response']! as Map<String, Object?>,
    ),
    recordedAt: json['recordedAt'] as String?,
  );
}

/// A named collection of recorded interactions — the in-memory representation
/// of one cassette file. Persistence lives in `CassetteStore` so this stays
/// pure and unit-testable without dart:io.
class Cassette {
  Cassette(this.name, {Map<String, Interaction>? interactions})
    : _byKey = interactions ?? <String, Interaction>{};

  /// The current on-disk schema version. Bump on breaking format changes.
  static const int formatVersion = 1;

  final String name;
  final Map<String, Interaction> _byKey;

  Iterable<Interaction> get interactions => _byKey.values;
  int get length => _byKey.length;
  bool get isEmpty => _byKey.isEmpty;

  /// The interaction matching [key], or null on a miss.
  Interaction? find(String key) => _byKey[key];

  /// Convenience: fingerprint [request] and look it up.
  Interaction? match(Map<String, Object?> request) =>
      find(fingerprintRequest(request));

  /// Insert or overwrite an interaction.
  void put(Interaction interaction) => _byKey[interaction.key] = interaction;

  /// Remove an interaction by key; returns whether one was present.
  bool remove(String key) => _byKey.remove(key) != null;

  Map<String, Object?> toJson() => {
    'version': formatVersion,
    'name': name,
    'interactions': interactions.map((i) => i.toJson()).toList(),
  };

  static Cassette fromJson(Map<String, Object?> json) {
    final version = (json['version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      throw CassetteFormatException(
        'Cassette "${json['name']}" was written with format v$version but this '
        'version of llm_replay_eval only understands v$formatVersion. '
        'Upgrade the package or re-record.',
      );
    }
    final cassette = Cassette(json['name'] as String? ?? 'cassette');
    for (final raw
        in (json['interactions'] as List? ?? const [])
            .cast<Map<String, Object?>>()) {
      cassette.put(Interaction.fromJson(raw));
    }
    return cassette;
  }
}

/// Thrown when a cassette file cannot be understood (corrupt or too new).
class CassetteFormatException implements Exception {
  CassetteFormatException(this.message);
  final String message;
  @override
  String toString() => 'CassetteFormatException: $message';
}
