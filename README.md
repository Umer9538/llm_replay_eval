# llm_replay_eval

[![pub package](https://img.shields.io/pub/v/llm_replay_eval.svg)](https://pub.dev/packages/llm_replay_eval)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Deterministic record/replay ("cassettes") and evaluation for on-device LLM inference in Flutter.** Record real inference once on a device, then replay it forever — your AI-feature tests run **fast, offline, and byte-identical every time.**

```dart
final answer = await session.run(
  request: {'prompt': prompt, 'model': 'gemma-2b', 'temperature': 0},
  live: () => gemma.getResponse(prompt), // your real on-device call
);
```

---

## Why this exists

HTTP VCRs (`dartvcr`, `http_mock_adapter`, …) record network traffic. But **on-device models never touch the network** — flutter_gemma, cactus, llama_cpp_dart and friends run the model *in-process*. There is no HTTP request to intercept, so HTTP VCRs are blind to them.

That leaves on-device AI features in a bad spot for testing:

- **Slow** — every test run re-runs real inference (seconds per call, model load on top).
- **Flaky** — LLM output is non-deterministic, so assertions wobble.
- **Device-bound** — CI can't run the model at all without a GPU/emulator.

`llm_replay_eval` records at the **inference boundary** instead of the network. You capture the real model's output once (on a device), commit the cassette, and every subsequent test replays it instantly with zero device, zero network, and zero non-determinism.

## Install

```yaml
dev_dependencies:
  llm_replay_eval: ^0.1.0
```

## The workflow: record once, replay forever

It mirrors VCR / `--update-goldens`:

1. **Record** on a real device/emulator where the model actually runs:
   ```bash
   flutter test integration_test/ --dart-define=LLM_REPLAY_MODE=record
   ```
2. **Commit** the generated `*.cassette.json` files (they're pretty-printed JSON — clean git diffs).
3. **Replay** in CI and local unit tests — no device, no model, instant:
   ```bash
   flutter test   # LLM_REPLAY_MODE defaults to replay; a miss fails loudly
   ```

```dart
import 'package:llm_replay_eval/llm_replay_eval.dart';

final session = ReplaySession.open(
  name: 'chat',
  store: CassetteStore('test/cassettes'),
  mode: replayModeFromString(
    const String.fromEnvironment('LLM_REPLAY_MODE'),
    fallback: ReplayMode.replay, // CI is hermetic by default
  ),
);

// Runtime-agnostic: works with flutter_gemma, cactus, llama_cpp_dart, or your own.
final reply = await session.run(
  request: {'prompt': 'Capital of France?', 'model': 'gemma-2b', 'temperature': 0},
  live: () => myModel.generateResponse('Capital of France?'),
);

session.flush(); // persist anything newly recorded
expect(reply, contains('Paris'));
```

Streaming works the same way:

```dart
final tokens = session.runStream(
  request: {'prompt': prompt, 'model': 'gemma-2b'},
  live: () => myModel.generateResponseAsync(prompt), // Stream<String>
);
await for (final tok in tokens) { /* … */ }
```

### Three modes

| Mode | Behavior | Use for |
|------|----------|---------|
| `replay` | Serve from cassette; **a miss is a hard failure** | CI — hermetic & offline |
| `record` | Always call the real model and (over)write the cassette | Refreshing cassettes on a device |
| `auto` | Serve if recorded, otherwise record the miss | Local development |

## Evaluation: assertions that survive replay

Recording the *output* is half the battle. The other half is checking it. `llm_replay_eval` ships eval matchers that run against replayed output — so your evals are deterministic too.

```dart
final report = await EvalSuite('faq', [
  EvalCase(
    name: 'capital of France',
    request: {'prompt': 'Capital of France?', 'model': 'gemma-2b'},
    infer: () => myModel.generateResponse('Capital of France?'),
    checks: [ContainsText('Paris'), MaxOutputLength(200)],
  ),
  EvalCase(
    name: 'returns valid JSON',
    request: {'prompt': 'List 3 fruits as JSON', 'model': 'gemma-2b'},
    infer: () => myModel.generateResponse('List 3 fruits as JSON'),
    checks: [IsValidJson(), JsonHasKeys(['fruits'])],
  ),
]).run(session);

print(report.summary());      // Eval "faq": 2/2 passed (100.0%)
expect(report.passed, isTrue);
```

Single assertions plug straight into `expect` via `satisfies`:

```dart
expect(reply, satisfies(ContainsText('Paris', caseSensitive: false)));
```

Built-in deterministic matchers: `ContainsText`, `MatchesPattern`, `EqualsText`, `IsValidJson`, `JsonHasKeys`, `JsonFieldEquals`, `MaxOutputLength`, `MaxTokens`.

### LLM-as-judge — that also replays

The headline eval feature: grade outputs with a model, but route the judge call through a `ReplaySession` so **the verdict is recorded once and replayed deterministically**. Your "LLM-as-judge" suite becomes offline and reproducible in CI — something a plain judge can't be.

```dart
final judge = LlmJudge(
  session: judgeSession,                 // cassetted, like everything else
  rubric: 'Is the answer factually correct and concise?',
  judge: (prompt) => judgeModel.generateResponse(prompt),
);

final result = await judge.evaluate(EvalInput(reply));
expect(result.passed, isTrue);           // deterministic on replay
```

The judge's reply is parsed leniently (JSON `{score, pass, reason}`, PASS/FAIL keywords, or a bare score) and **fails closed** if unparseable, so a confused judge never silently passes a test.

## How it compares

| | HTTP VCR (`dartvcr`) | `llm_replay_eval` |
|---|---|---|
| Records network calls | ✅ | n/a |
| Records **in-process / on-device** inference | ❌ (no network to see) | ✅ |
| Streaming token replay | ❌ | ✅ |
| Deterministic, committable cassettes | ✅ | ✅ |
| Eval matchers + dataset runner | ❌ | ✅ |
| LLM-as-judge that replays offline | ❌ | ✅ |

## Design notes

- **Runtime-agnostic.** No dependency on any specific runtime — you supply the `live` thunk, so it works with flutter_gemma, cactus, llama_cpp_dart, remote APIs, or a custom engine.
- **Deterministic cassettes.** Timestamps and timing are omitted by default, so re-recording an unchanged interaction yields a byte-identical file. Git diffs stay meaningful.
- **Canonical fingerprints.** Requests are hashed (sha256) over a key-order-independent canonical form, with binary payloads (multimodal images/audio) reduced to a digest — so a 4 MB image becomes a short, stable key.
- **Fails loud, not silent.** A replay miss throws an actionable `CassetteMissException` telling you exactly how to record it.

## Roadmap

- **v0.2** — zero-config platform-channel auto-interception for flutter_gemma (no code changes), latency budgets, semantic-similarity matcher.
- Later — an MCP server so an agent can run an eval suite and read the report as a tool call.

## License

MIT © Muhammad Umer
