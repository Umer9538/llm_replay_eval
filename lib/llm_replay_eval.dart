/// Deterministic record/replay ("cassettes") and evaluation for on-device LLM
/// inference in Flutter.
///
/// HTTP VCRs can't help you here: on-device models never touch the network.
/// llm_replay_eval records at the inference boundary instead — so your AI-feature
/// tests run fast, offline, and byte-identical every time, even for in-process
/// models.
library;
