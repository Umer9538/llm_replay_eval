import 'dart:convert';
import 'dart:io';

import 'cassette.dart';

/// Loads and saves [Cassette]s as JSON files on disk.
///
/// Cassettes are written as pretty-printed JSON so they diff cleanly in code
/// review — a reviewer can see exactly which recorded responses changed. Files
/// are named `<cassetteName>.cassette.json` inside [directory].
///
/// This is the only part of the engine that touches dart:io, keeping the rest
/// of the package pure and unit-testable.
class CassetteStore {
  CassetteStore(this.directory);

  /// Directory holding cassette files (created on save if absent).
  final String directory;

  static const String _suffix = '.cassette.json';
  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  /// The path a cassette with [name] would occupy.
  String pathFor(String name) =>
      '$directory${Platform.pathSeparator}$name$_suffix';

  /// Loads the cassette named [name], or returns an empty one if no file
  /// exists yet (so first-run recording "just works").
  Cassette load(String name) {
    final file = File(pathFor(name));
    if (!file.existsSync()) return Cassette(name);
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw CassetteFormatException(
        'Cassette file ${file.path} is not a JSON object.',
      );
    }
    return Cassette.fromJson(decoded);
  }

  /// Persists [cassette] to disk, creating [directory] if needed.
  void save(Cassette cassette) {
    final dir = Directory(directory);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File(
      pathFor(cassette.name),
    ).writeAsStringSync('${_encoder.convert(cassette.toJson())}\n');
  }

  /// Whether a cassette file for [name] already exists.
  bool exists(String name) => File(pathFor(name)).existsSync();
}
