import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Produces a stable, canonical fingerprint for an inference request.
///
/// The same logical request always maps to the same cassette entry — regardless
/// of map key ordering or insignificant formatting. This is what makes cassette
/// hits reliable rather than flaky.
///
/// [request] must be JSON-encodable. Binary payloads (images/audio for
/// multimodal models) should be reduced to a digest string by the caller
/// before fingerprinting — see [digestBytes] — so a 4 MB image becomes a short,
/// stable key instead of being inlined.
String fingerprintRequest(Map<String, Object?> request) {
  final canonical = jsonEncode(canonicalize(request));
  return sha256.convert(utf8.encode(canonical)).toString();
}

/// A short, stable digest of binary data, suitable for embedding inside a
/// request map before fingerprinting.
String digestBytes(List<int> bytes) => sha256.convert(bytes).toString();

/// Recursively sorts map keys so that two semantically-equal structures encode
/// to identical JSON. Exposed for testing and for callers that want to store a
/// canonical copy of the request alongside its fingerprint.
Object? canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return <String, Object?>{for (final k in keys) k: canonicalize(value[k])};
  }
  if (value is Iterable) {
    return value.map(canonicalize).toList();
  }
  return value;
}
