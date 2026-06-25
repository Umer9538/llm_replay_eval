## 0.1.0

Initial release.

* **Cassette engine** — deterministic record/replay of on-device LLM inference.
  Canonical sha256 request fingerprinting (key-order independent, multimodal-safe),
  one-shot and streaming responses, versioned JSON cassettes that diff cleanly.
* **`ReplaySession`** — runtime-agnostic wrapper for any inference call
  (flutter_gemma, cactus, llama_cpp_dart, remote, or custom). `record` / `replay` /
  `auto` modes, with actionable `CassetteMissException` on a replay miss.
* **Eval matchers** — `ContainsText`, `MatchesPattern`, `EqualsText`, `IsValidJson`,
  `JsonHasKeys`, `JsonFieldEquals`, `MaxOutputLength`, `MaxTokens`, plus a
  `satisfies()` bridge for use in `expect`.
* **Cassetted `LlmJudge`** — LLM-as-judge whose verdict is itself recorded and
  replayed, making judge-based evals offline and deterministic in CI.
* **`EvalSuite`** — dataset runner with pass-rate aggregation and JSON reporting.
