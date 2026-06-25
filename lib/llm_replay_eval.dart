/// Deterministic record/replay ("cassettes") and evaluation for on-device LLM
/// inference in Flutter.
///
/// HTTP VCRs can't help you here: on-device models never touch the network.
/// llm_replay_eval records at the inference boundary instead — so your AI-feature
/// tests run fast, offline, and byte-identical every time, even for in-process
/// models.
library;

// --- Cassette engine (record/replay core) -----------------------------------
export 'src/cassette.dart';
export 'src/cassette_store.dart';
export 'src/fingerprint.dart';
export 'src/replay_mode.dart';

// --- Integration (runtime-agnostic record/replay session) -------------------
export 'src/replay_session.dart';
