# Ollama Context-Window Resolution + Context-Occupancy Gauge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop Ollama silently truncating uncatalogued models at `num_ctx: 2048` by resolving each model's real context window (catalog → daemon `/api/show` → base-name → default), and surface a true context-occupancy gauge in the status bar.

**Architecture:** `OllamaClient` resolves its context window once, lazily, on the first `stream()` call (because `createClient` is synchronous and cannot await the daemon). It always injects `num_ctx`. The *real* resolved window (never the 8192 fallback) is exposed via a new `LlmClient.contextWindow` getter so the App can use it as a gauge denominator. `AgentCore` records the last turn's billed input as the gauge numerator. A pure `formatContextGauge` formatter renders `used/window (pct)` and the App wires it into the status bar.

**Tech Stack:** Dart, `package:http`, `package:test`. Monorepo: `packages/glue_core`, `packages/glue_strategies`, `packages/glue_harness`, `cli/`.

## Global Constraints

- Imports: always `package:glue/`, `package:glue_core/`, `package:glue_strategies/`, `package:glue_harness/` — never relative (`always_use_package_imports`).
- Zero-warning policy: `dart analyze --fatal-infos` must pass.
- `dart format` must leave files unchanged before commit.
- Run all `dart` commands from `cli/` unless the package is stated otherwise.
- TDD: failing test first, minimal code, green, commit.
- Existing constants to reuse (do not redefine): `ollamaNumCtxCeiling = 131072` in `packages/glue_strategies/lib/src/llm/ollama_client.dart`.
- Fail-soft for all daemon network calls: any timeout / non-200 / malformed JSON collapses to `null`, never throws.

---

### Task 1: `OllamaDiscovery.showContextLength` — daemon `/api/show` lookup

**Files:**
- Modify: `packages/glue_strategies/lib/src/providers/ollama_discovery.dart`
- Test: `cli/test/providers/ollama_discovery_test.dart`

**Interfaces:**
- Produces: `Future<int?> OllamaDiscovery.showContextLength(String tag)` — POSTs `/api/show {name: tag}`, returns the first `model_info` value whose key ends in `.context_length`, or `null` on any failure / absence.

- [ ] **Step 1: Write the failing test**

Add to `cli/test/providers/ollama_discovery_test.dart` (reuse the file's existing fake-http harness; if it builds clients via a `clientFactory`, mirror that — the snippet below shows a self-contained fake):

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:glue_strategies/glue_strategies.dart';
import 'package:test/test.dart';

class _FakeHttp extends http.BaseClient {
  _FakeHttp(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest req) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

http.StreamedResponse _json(int status, String body) => http.StreamedResponse(
  Stream<List<int>>.value(utf8.encode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('OllamaDiscovery.showContextLength', () {
    test('reads model_info.<arch>.context_length', () async {
      final disco = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => _FakeHttp(
          (req) async {
            expect(req.url.path, endsWith('/api/show'));
            return _json(200, jsonEncode({
              'model_info': {
                'general.architecture': 'gemma3',
                'gemma3.context_length': 131072,
                'gemma3.embedding_length': 3584,
              },
            }));
          },
        ),
      );

      expect(await disco.showContextLength('gemma4:latest'), 131072);
    });

    test('returns null when no *.context_length key exists', () async {
      final disco = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => _FakeHttp(
          (_) async => _json(200, jsonEncode({'model_info': {'a.b': 1}})),
        ),
      );
      expect(await disco.showContextLength('x'), isNull);
    });

    test('fail-soft to null on non-200', () async {
      final disco = OllamaDiscovery(
        baseUrl: Uri.parse('http://localhost:11434'),
        clientFactory: () => _FakeHttp((_) async => _json(404, 'nope')),
      );
      expect(await disco.showContextLength('x'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cli && dart test test/providers/ollama_discovery_test.dart -N showContextLength`
Expected: FAIL — `showContextLength` is not defined.

- [ ] **Step 3: Write minimal implementation**

In `ollama_discovery.dart`, add a `_showUri()` helper next to `_tagsUri()`:

```dart
  Uri _showUri() => baseUrl.replace(path: '${_stripV1(baseUrl.path)}api/show');
```

And add the public method (place it after `listInstalled`):

```dart
  /// `POST /api/show`. Returns the model's trained context length from
  /// `model_info.<arch>.context_length`, or `null` on any failure or when
  /// the daemon does not report it. Never throws.
  Future<int?> showContextLength(String tag) async {
    final client = _clientFactory();
    try {
      final response = await client
          .post(
            _showUri(),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'name': tag}),
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final info = decoded['model_info'];
      if (info is! Map) return null;
      for (final entry in info.entries) {
        if (entry.key is String &&
            (entry.key as String).endsWith('.context_length')) {
          final value = entry.value;
          if (value is num) return value.toInt();
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd cli && dart test test/providers/ollama_discovery_test.dart -N showContextLength`
Expected: PASS (3 tests).

- [ ] **Step 5: Analyze + commit**

```bash
cd cli && dart format ../packages/glue_strategies/lib/src/providers/ollama_discovery.dart test/providers/ollama_discovery_test.dart && dart analyze --fatal-infos
git add packages/glue_strategies/lib/src/providers/ollama_discovery.dart cli/test/providers/ollama_discovery_test.dart
git commit -m "feat(ollama): add OllamaDiscovery.showContextLength via /api/show"
```

---

### Task 2: `LlmClient.contextWindow` default getter

**Files:**
- Modify: `packages/glue_core/lib/src/llm_client.dart`
- Test: `packages/glue_core/test/llm_client_test.dart` (create if absent)

**Interfaces:**
- Produces: `int? get contextWindow` on `LlmClient`, defaulting to `null`. Subclasses may override.

- [ ] **Step 1: Write the failing test**

Create `packages/glue_core/test/llm_client_test.dart`:

```dart
import 'package:glue_core/glue_core.dart';
import 'package:test/test.dart';

class _StubClient implements LlmClient {
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) =>
      const Stream.empty();
}

void main() {
  test('LlmClient.contextWindow defaults to null', () {
    expect(_StubClient().contextWindow, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/glue_core && dart test test/llm_client_test.dart`
Expected: FAIL — `contextWindow` is not defined on `LlmClient` (and `_StubClient` would not satisfy a member it must implement once added).

- [ ] **Step 3: Write minimal implementation**

In `packages/glue_core/lib/src/llm_client.dart`, inside `abstract class LlmClient`, add below `stream`:

```dart
  /// The model's effective context window in tokens, when known. Used as
  /// the denominator for the context-occupancy gauge. Defaults to `null`
  /// (unknown); clients that can resolve it (e.g. Ollama) override this.
  int? get contextWindow => null;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/glue_core && dart test test/llm_client_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
cd packages/glue_core && dart format lib/src/llm_client.dart test/llm_client_test.dart && dart analyze --fatal-infos
cd ../.. && git add packages/glue_core/lib/src/llm_client.dart packages/glue_core/test/llm_client_test.dart
git commit -m "feat(core): add LlmClient.contextWindow getter defaulting to null"
```

---

### Task 3: `OllamaClient` lazy window resolution + always-inject `num_ctx` + getter

**Files:**
- Modify: `packages/glue_strategies/lib/src/llm/ollama_client.dart`
- Test: `cli/test/llm/ollama_client_test.dart`

**Interfaces:**
- Consumes: `OllamaDiscovery.showContextLength` (Task 1); `LlmClient.contextWindow` (Task 2); `ollamaNumCtxCeiling`.
- Produces:
  - New constructor params `int? contextWindowFallback` (base-name catalog hint).
  - New const `int ollamaDefaultNumCtx = 8192`.
  - Resolution priority: `contextWindow (exact catalog) ?? daemon /api/show ?? contextWindowFallback`. `num_ctx = min(real ?? ollamaDefaultNumCtx, ollamaNumCtxCeiling)`, always injected.
  - Override `int? get contextWindow` returns the **real** resolved window (`null` when only the 8192 default applied).

- [ ] **Step 1: Write the failing tests**

Append to `cli/test/llm/ollama_client_test.dart` (the file already has `_FakeHttp` + `_rawResponse`). Add a helper that answers both `/api/show` and `/api/chat`, capturing the chat body:

```dart
  group('OllamaClient.stream — num_ctx resolution', () {
    // Returns [capturedChatBody-holder, fakeHttp]. /api/show -> showBody,
    // /api/chat -> a single done frame with usage.
    ({List<Map<String, dynamic>?> chatBody, _FakeHttp http}) harness({
      String? showJson,
    }) {
      final holder = <Map<String, dynamic>?>[null];
      final http = _FakeHttp((req) async {
        if (req.url.path.endsWith('/api/show')) {
          return _rawResponse(showJson == null ? 404 : 200, showJson ?? 'no');
        }
        holder[0] = jsonDecode((req as http.Request).body)
            as Map<String, dynamic>;
        return _rawResponse(
          200,
          '${jsonEncode({
            'message': {'role': 'assistant', 'content': 'ok'},
            'done': true,
            'prompt_eval_count': 5,
            'eval_count': 2,
          })}\n',
        );
      });
      return (chatBody: holder, http: http);
    }

    test('exact catalog window is injected as num_ctx (no daemon call)',
        () async {
      final h = harness();
      final ollama = OllamaClient(
        model: 'gemma4:26b',
        systemPrompt: '',
        contextWindow: 256000,
        requestClientFactory: () => h.http,
      );
      await ollama.stream([Message.user('hi')]).toList();
      expect(h.chatBody[0]!['options']['num_ctx'], 131072); // capped at ceiling
      expect(ollama.contextWindow, 256000);
    });

    test('uncatalogued tag resolves via daemon /api/show', () async {
      final h = harness(
        showJson: jsonEncode({'model_info': {'gemma3.context_length': 32768}}),
      );
      final ollama = OllamaClient(
        model: 'gemma4:latest',
        systemPrompt: '',
        requestClientFactory: () => h.http,
      );
      await ollama.stream([Message.user('hi')]).toList();
      expect(h.chatBody[0]!['options']['num_ctx'], 32768);
      expect(ollama.contextWindow, 32768);
    });

    test('falls back to base-name hint when daemon has nothing', () async {
      final h = harness(); // /api/show -> 404
      final ollama = OllamaClient(
        model: 'gemma4:latest',
        systemPrompt: '',
        contextWindowFallback: 256000,
        requestClientFactory: () => h.http,
      );
      await ollama.stream([Message.user('hi')]).toList();
      expect(h.chatBody[0]!['options']['num_ctx'], 131072); // capped
      expect(ollama.contextWindow, 256000);
    });

    test('default 8192 num_ctx when nothing resolves; getter stays null',
        () async {
      final h = harness(); // /api/show -> 404, no fallback
      final ollama = OllamaClient(
        model: 'mystery:latest',
        systemPrompt: '',
        requestClientFactory: () => h.http,
      );
      await ollama.stream([Message.user('hi')]).toList();
      expect(h.chatBody[0]!['options']['num_ctx'], ollamaDefaultNumCtx);
      expect(ollama.contextWindow, isNull); // default is not a real window
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd cli && dart test test/llm/ollama_client_test.dart -N "num_ctx resolution"`
Expected: FAIL — `contextWindowFallback` / `ollamaDefaultNumCtx` undefined; getter absent.

- [ ] **Step 3: Write the implementation**

In `ollama_client.dart`:

(a) Add the default const near `ollamaNumCtxCeiling`:

```dart
/// Default `num_ctx` for Ollama models whose real context window could not
/// be resolved from the catalog or the daemon. Anything but Ollama's silent
/// 2048 default; deliberately conservative so mid-range GPUs stay safe.
const int ollamaDefaultNumCtx = 8192;
```

(b) Extend the constructor and fields. Replace the `contextWindow` field block and constructor with:

```dart
  /// Exact catalog context window, when the model id is catalogued. Null for
  /// passthrough tags (e.g. `gemma4:latest`).
  final int? _exactContextWindow;

  /// Base-name catalog hint from the adapter (`gemma4:latest` -> `gemma4:26b`).
  /// Used only if the daemon reports nothing.
  final int? _contextWindowFallback;

  final Uri _baseUri;

  // Resolved once on first stream(); see _ensureResolved.
  bool _resolved = false;
  int? _resolvedRealWindow; // catalog/daemon/fallback — never the default
  int _numCtx = ollamaDefaultNumCtx;

  OllamaClient({
    required this.model,
    required this.systemPrompt,
    String baseUrl = 'http://localhost:11434',
    int? contextWindow,
    int? contextWindowFallback,
    http.Client Function()? requestClientFactory,
  })  : _exactContextWindow = contextWindow,
        _contextWindowFallback = contextWindowFallback,
        _requestClientFactory = requestClientFactory ?? http.Client.new,
        _baseUri = Uri.parse(baseUrl);

  @override
  int? get contextWindow => _resolvedRealWindow;
```

(c) Add the resolver:

```dart
  /// Resolve the real context window once: exact catalog -> daemon
  /// /api/show -> base-name fallback. Sizes _numCtx (capped at the
  /// ceiling), defaulting to ollamaDefaultNumCtx when nothing resolves.
  Future<void> _ensureResolved() async {
    if (_resolved) return;
    _resolved = true;
    var real = _exactContextWindow;
    if (real == null) {
      final daemon = await OllamaDiscovery(
        baseUrl: _baseUri,
        clientFactory: _requestClientFactory,
      ).showContextLength(model);
      real = daemon ?? _contextWindowFallback;
    }
    _resolvedRealWindow = real;
    final effective = real ?? ollamaDefaultNumCtx;
    _numCtx = effective < ollamaNumCtxCeiling ? effective : ollamaNumCtxCeiling;
  }
```

(d) Convert `stream` to `async*` so it can await resolution, and always inject `num_ctx`:

```dart
  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    await _ensureResolved();
    const mapper = OllamaMessageMapper();
    final mapped = mapper.mapMessages(messages, systemPrompt: systemPrompt);

    final body = <String, dynamic>{
      'model': model,
      'messages': mapped.messages,
      'stream': true,
      'options': <String, dynamic>{'num_ctx': _numCtx},
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = const OpenAiToolEncoder().encodeAll(tools);
    }

    yield* sendAndStream(
      requestClientFactory: _requestClientFactory,
      uri: _baseUri.resolve('/api/chat'),
      headers: const {'Content-Type': 'application/json'},
      body: body,
      providerName: 'Ollama',
      parse: (bytes) => parseStreamEvents(decodeNdjson(bytes)),
      classifyError: (status, errorBody) {
        if (status == 400 &&
            errorBody.toLowerCase().contains('does not support tools')) {
          throw ToolsNotSupportedException(model);
        }
        throw Exception('Ollama API error $status: $errorBody');
      },
    );
  }
```

Add `import 'package:glue_strategies/src/providers/ollama_discovery.dart';` if not already imported. Update the class docstring's `num_ctx` paragraph to note the always-inject + default behavior.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd cli && dart test test/llm/ollama_client_test.dart`
Expected: PASS (existing tests + 4 new ones). The pre-existing error-translation tests still pass because `_FakeHttp` answers `/api/show` with 404 → falls through to the chat error path.

- [ ] **Step 5: Analyze + commit**

```bash
cd cli && dart format ../packages/glue_strategies/lib/src/llm/ollama_client.dart test/llm/ollama_client_test.dart && dart analyze --fatal-infos
git add packages/glue_strategies/lib/src/llm/ollama_client.dart cli/test/llm/ollama_client_test.dart
git commit -m "fix(ollama): resolve real context window and always inject num_ctx"
```

---

### Task 4: `OllamaAdapter` passes the base-name fallback hint

**Files:**
- Modify: `packages/glue_strategies/lib/src/providers/ollama_adapter.dart`
- Test: `cli/test/providers/ollama_adapter_test.dart`

**Interfaces:**
- Consumes: `OllamaClient(contextWindow:, contextWindowFallback:)` (Task 3); `ResolvedModel.provider.models` (`Map<String, ModelDef>`), `model.apiId`, `model.def.contextWindow`.
- Produces: a private base-name matcher; `createClient` passes `contextWindow: model.def.contextWindow` and `contextWindowFallback: <base-name match>.contextWindow`.

- [ ] **Step 1: Write the failing test**

Add to `cli/test/providers/ollama_adapter_test.dart` (follow the file's existing construction of `ResolvedProvider`/`ResolvedModel`; the assertion targets the base-name helper, exposed for testing):

```dart
  group('OllamaAdapter base-name context fallback', () {
    test('matches gemma4:latest to a catalogued gemma4:* entry', () {
      final models = {
        'gemma4:26b': ModelDef(id: 'gemma4:26b', name: 'g', contextWindow: 256000),
      };
      expect(OllamaAdapter.baseNameContextWindow('gemma4:latest', models),
          256000);
    });

    test('returns null when no family member is catalogued', () {
      expect(OllamaAdapter.baseNameContextWindow('mystery:latest', const {}),
          isNull);
    });

    test('exact id is left to the normal path (no base-name match needed)', () {
      final models = {
        'gemma4:26b': ModelDef(id: 'gemma4:26b', name: 'g', contextWindow: 256000),
      };
      // base name of gemma4:26b is gemma4; still resolves the family window.
      expect(OllamaAdapter.baseNameContextWindow('gemma4:26b', models), 256000);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cli && dart test test/providers/ollama_adapter_test.dart -N "base-name context fallback"`
Expected: FAIL — `baseNameContextWindow` is not defined.

- [ ] **Step 3: Write minimal implementation**

In `ollama_adapter.dart`, add a static helper and use it in `createClient`:

```dart
  /// First catalogued context window for a tag's family. `gemma4:latest`
  /// matches any `gemma4:*` entry. Used only as a fallback when the exact
  /// tag is uncatalogued and the daemon reports nothing.
  static int? baseNameContextWindow(String tag, Map<String, ModelDef> models) {
    final base = tag.split(':').first;
    for (final entry in models.entries) {
      if (entry.key.split(':').first == base &&
          entry.value.contextWindow != null) {
        return entry.value.contextWindow;
      }
    }
    return null;
  }
```

Update `createClient`'s `OllamaClient(...)` call:

```dart
    return OllamaClient(
      model: model.apiId,
      systemPrompt: systemPrompt,
      baseUrl: stripV1Suffix(provider.baseUrl ?? 'http://localhost:11434'),
      contextWindow: model.def.contextWindow,
      contextWindowFallback:
          baseNameContextWindow(model.apiId, provider.models),
      requestClientFactory: _requestClientFactory,
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd cli && dart test test/providers/ollama_adapter_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
cd cli && dart format ../packages/glue_strategies/lib/src/providers/ollama_adapter.dart test/providers/ollama_adapter_test.dart && dart analyze --fatal-infos
git add packages/glue_strategies/lib/src/providers/ollama_adapter.dart cli/test/providers/ollama_adapter_test.dart
git commit -m "feat(ollama): pass base-name context-window fallback to client"
```

---

### Task 5: `AgentCore.lastTurnInputTokens` — gauge numerator

**Files:**
- Modify: `packages/glue_harness/lib/src/agent/agent_core.dart`
- Test: `cli/test/agent_core_test.dart`

**Interfaces:**
- Produces: `int AgentCore.lastTurnInputTokens` (default 0), set to `inputTokens + cacheReadTokens` after each completed turn's LLM stream.

- [ ] **Step 1: Write the failing test**

`cli/test/agent_core_test.dart` already defines a fake `LlmClient` (yields `LlmChunk`s incl. `UsageInfo`). Add:

```dart
  test('lastTurnInputTokens reflects billed input of the latest turn',
      () async {
    // Fake client that yields text + a UsageInfo with input + cache-read,
    // then no tool calls so the loop ends after one turn.
    final client = _UsageFake(
      input: 1200,
      cacheRead: 300,
      output: 40,
    );
    final agent = AgentCore(llm: client, tools: {}, modelId: 'test');
    await agent.run('hello').toList();
    expect(agent.lastTurnInputTokens, 1500); // 1200 + 300
  });
```

Add a minimal `_UsageFake` near the file's other fakes (model it on the existing fake — yield one `TextDelta` then a `UsageInfo`, then complete):

```dart
class _UsageFake implements LlmClient {
  _UsageFake({required this.input, required this.cacheRead, required this.output});
  final int input;
  final int cacheRead;
  final int output;

  @override
  Stream<LlmChunk> stream(List<Message> messages, {List<Tool>? tools}) async* {
    yield const TextDelta('hi');
    yield UsageInfo(
      inputTokens: input,
      outputTokens: output,
      cacheReadTokens: cacheRead,
    );
  }
}
```

(If `cli/test/agent_core_test.dart` already imports the needed symbols, skip duplicate imports; otherwise add `package:glue_core/glue_core.dart` and `package:glue_harness/glue_harness.dart`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cli && dart test test/agent_core_test.dart -N "lastTurnInputTokens"`
Expected: FAIL — `lastTurnInputTokens` is not defined.

- [ ] **Step 3: Write minimal implementation**

In `agent_core.dart`, add the field near `stats` (~line 45):

```dart
  /// Billed input tokens of the most recent completed turn (uncached input +
  /// cache reads) — i.e. what the model actually saw. The numerator for the
  /// status-bar context-occupancy gauge. Distinct from [stats], which is the
  /// cumulative lifetime total. Zero until the first turn completes.
  int lastTurnInputTokens = 0;
```

In the `finally` block after the per-turn stream loop (where `billableInput` is computed, ~line 240), set the field. Add it just inside `finally {` so it is set on every real turn (the tools-not-supported path `continue`s before reaching this block, so a retry simply overwrites on the next turn):

```dart
        } finally {
          lastTurnInputTokens = inputTokens + cacheReadTokens;
          // ...existing span-finalisation code unchanged...
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd cli && dart test test/agent_core_test.dart -N "lastTurnInputTokens"`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
cd cli && dart format ../packages/glue_harness/lib/src/agent/agent_core.dart test/agent_core_test.dart && dart analyze --fatal-infos
git add packages/glue_harness/lib/src/agent/agent_core.dart cli/test/agent_core_test.dart
git commit -m "feat(agent): track lastTurnInputTokens for the context gauge"
```

---

### Task 6: `formatContextGauge` — pure formatter

**Files:**
- Modify: `cli/lib/src/extensions/token_format.dart`
- Test: `cli/test/token_format_test.dart` (create if absent)

**Interfaces:**
- Consumes: `formatCompactTokens` (same file).
- Produces: `String? formatContextGauge(int used, int? window)` → `"<used>/<window> ctx (<pct>%)"`, or `null` when `window == null || window <= 0 || used <= 0`.

- [ ] **Step 1: Write the failing test**

Create `cli/test/token_format_test.dart`:

```dart
import 'package:glue/src/extensions/token_format.dart';
import 'package:test/test.dart';

void main() {
  group('formatContextGauge', () {
    test('formats used/window with rounded percent', () {
      expect(formatContextGauge(14325, 131072), '14k/131k ctx (11%)');
    });
    test('null window -> null (gauge hidden)', () {
      expect(formatContextGauge(14325, null), isNull);
    });
    test('zero/non-positive window -> null', () {
      expect(formatContextGauge(14325, 0), isNull);
    });
    test('zero used -> null (no turn yet)', () {
      expect(formatContextGauge(0, 131072), isNull);
    });
  });
}
```

(Confirm `formatCompactTokens(14325) == '14k'` and `formatCompactTokens(131072) == '131k'` per the existing implementation — `>= 10000` yields `'<n~/1000>k'`. Adjust the expected string only if the existing formatter differs.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cli && dart test test/token_format_test.dart`
Expected: FAIL — `formatContextGauge` is not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `cli/lib/src/extensions/token_format.dart`:

```dart
/// Context-occupancy gauge: `14k/131k ctx (11%)`. Numerator is the latest
/// turn's billed input (what the model saw); denominator is the resolved
/// context window. Returns `null` — so the caller omits the segment — when
/// the window is unknown/non-positive or no turn has run yet.
String? formatContextGauge(int used, int? window) {
  if (window == null || window <= 0 || used <= 0) return null;
  final pct = (used * 100 / window).round();
  return '${formatCompactTokens(used)}/${formatCompactTokens(window)} '
      'ctx ($pct%)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd cli && dart test test/token_format_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

```bash
cd cli && dart format lib/src/extensions/token_format.dart test/token_format_test.dart && dart analyze --fatal-infos
git add cli/lib/src/extensions/token_format.dart cli/test/token_format_test.dart
git commit -m "feat(cli): add formatContextGauge status-bar formatter"
```

---

### Task 7: Wire the gauge into the status bar

**Files:**
- Modify: `cli/lib/src/app.dart` (status bar render, ~line 1093-1104)

**Interfaces:**
- Consumes: `agent.lastTurnInputTokens` (Task 5), `agent.llm.contextWindow` (Tasks 2-3), `formatContextGauge` (Task 6), `_config?.resolveModel(...).def.contextWindow`.

- [ ] **Step 1: Add the gauge segment**

In `app.dart`, just before the `rightSegs` list is built, compute the denominator and gauge:

```dart
    final activeModel = _config?.activeModel;
    final catalogWindow = (activeModel != null)
        ? _config?.resolveModel(activeModel).def.contextWindow
        : null;
    final contextWindow = catalogWindow ?? agent.llm.contextWindow;
    final gaugeSeg = formatContextGauge(agent.lastTurnInputTokens, contextWindow);
```

Then insert `?gaugeSeg` into `rightSegs` immediately before the cumulative-tokens entry:

```dart
    final rightSegs = [
      formatStatusModelLabel(
        _config?.activeModel,
        _config?.catalogData,
        _modelId,
      ),
      modeLabel,
      ansiTruncate(shortCwd, 30),
      ?scrollSeg,
      ?mcpSeg,
      ?gaugeSeg,
      '${formatCompactTokens(agent.stats.totalTokens)} tokens',
    ];
```

(The `?gaugeSeg` collection-element-if-null spread matches the file's existing `?scrollSeg`/`?mcpSeg` style and omits the segment when null.)

- [ ] **Step 2: Analyze**

Run: `cd cli && dart format lib/src/app.dart && dart analyze --fatal-infos`
Expected: No issues.

- [ ] **Step 3: Manual verification (render wiring has no unit seam)**

```bash
cd cli && just build
GLUE_HOME=$(mktemp -d) ../dist/glue -m anthropic/claude-haiku-4-5 \
  -p "say hi" --json 2>/dev/null | head -c 80   # smoke: no crash
```

Then run an interactive turn against a catalogued model and confirm the status bar shows a `Nk/Nk ctx (N%)` segment after the first reply, sitting left of the `Nk tokens` spend figure. Against an uncatalogued Ollama tag with the daemon up, confirm the segment appears (daemon-resolved); with the daemon down it is absent (no fake denominator) while replies still work (num_ctx default protects against truncation).

- [ ] **Step 4: Run the broader gate + commit**

```bash
cd cli && dart analyze --fatal-infos && dart test test/token_format_test.dart test/agent_core_test.dart test/llm/ollama_client_test.dart test/providers
git add cli/lib/src/app.dart
git commit -m "feat(cli): show context-occupancy gauge in the status bar"
```

---

## Self-Review

**Spec coverage:**
- Fix 1 daemon `/api/show` → Task 1. ✅
- Fix 1 resolution order (exact → daemon → base-name → default 8192), always-inject, real-vs-guess getter → Task 3. ✅
- Fix 1 base-name hint from `provider.models` → Task 4. ✅
- `LlmClient.contextWindow` default getter → Task 2. ✅
- Fix 2 numerator `lastTurnInputTokens` → Task 5. ✅
- Fix 2 formatter (hide on null/≤0/zero-used) → Task 6. ✅
- Fix 2 denominator `catalog ?? agent.llm.contextWindow` + status-bar wiring → Task 7. ✅
- `token_count` semantics untouched → no task modifies `SessionManager.recordUsage`/`SessionMeta`. ✅

**Placeholder scan:** No TBD/TODO; every code step has concrete code. The one judgment call (exact expected strings in Tasks 3/6) is gated by an explicit "confirm against the existing formatter" instruction.

**Type consistency:** `contextWindow`/`contextWindowFallback` constructor params (Task 3) match the adapter call (Task 4). `lastTurnInputTokens : int` (Task 5) feeds `formatContextGauge(int, int?)` (Task 6) feeds the App call (Task 7). `OllamaDiscovery.showContextLength(String) -> Future<int?>` (Task 1) matches the call in Task 3. `LlmClient.contextWindow` getter (Task 2) is overridden in Task 3 and read in Task 7.

## Note on commits

The working tree already carries the earlier, unrelated print-mode session fix (`cli/lib/src/app.dart` modified + `cli/test/app/print_mode_session_test.dart` untracked). Before starting Task 1, decide whether to commit that work first so these commits stay scoped — see the execution handoff.
