# Interaction Modes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 4-value PermissionMode with a 3-value InteractionMode (code/architect/ask) + 2-value ApprovalMode (confirm/auto), copying the Roo Code/Kilo Code tool-group model.

**Architecture:** Modes control which tools the LLM can see via the existing `toolFilter` on `AgentCore`. Each tool is tagged with a `ToolGroup` (read/edit/command/mcp). Each mode declares which groups it allows. Architect mode allows edit tools only for `.md` files. Approval (confirm vs auto) is orthogonal and toggled separately.

**Tech Stack:** Dart, glue CLI codebase

---

## File Structure

| File | Responsibility | Action |
|------|---------------|--------|
| `cli/lib/src/config/interaction_mode.dart` | `InteractionMode` enum, `ApprovalMode` enum, `ToolGroup` enum, mode→group matrix | Create |
| `cli/lib/src/config/permission_mode.dart` | Old `PermissionMode` enum | Delete |
| `cli/lib/src/agent/tools.dart` | Add `ToolGroup get group` to `Tool` base class | Modify |
| `cli/lib/src/app/agent_orchestration.dart` | Replace `_syncToolFilterImpl` with group-based + path-based filtering | Modify |
| `cli/lib/src/orchestrator/permission_gate.dart` | Rewrite to use `InteractionMode` + `ApprovalMode` | Modify |
| `cli/lib/src/app.dart` | Replace `_permissionMode` field with `_interactionMode` + `_approvalMode` | Modify |
| `cli/lib/src/app/terminal_event_router.dart` | Shift+Tab cycles `InteractionMode` | Modify |
| `cli/lib/src/app/render_pipeline.dart` | Status bar shows mode + approval | Modify |
| `cli/lib/src/commands/builtin_commands.dart` | Add `/code`, `/architect`, `/ask`, `/approve` commands | Modify |
| `cli/lib/src/app/command_helpers.dart` | Update `/info` output | Modify |
| `cli/lib/src/config/glue_config.dart` | Parse `interaction_mode` + `approval_mode` from config | Modify |
| `cli/test/config/interaction_mode_test.dart` | Test new enums and mode→group matrix | Create |
| `cli/test/config/permission_mode_test.dart` | Old test | Delete |
| `cli/test/agent/tool_filter_test.dart` | Update for group-based filtering | Modify |
| `cli/test/orchestrator/permission_gate_test.dart` | Rewrite for new types | Modify |

---

## Chunk 1: Core Types

### Task 1: Create InteractionMode, ApprovalMode, and ToolGroup

**Files:**
- Create: `cli/lib/src/config/interaction_mode.dart`
- Test: `cli/test/config/interaction_mode_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// cli/test/config/interaction_mode_test.dart
import 'package:test/test.dart';
import 'package:glue/src/config/interaction_mode.dart';

void main() {
  group('ToolGroup', () {
    test('all groups are defined', () {
      expect(ToolGroup.values, hasLength(4));
      expect(ToolGroup.values, containsAll([
        ToolGroup.read, ToolGroup.edit, ToolGroup.command, ToolGroup.mcp,
      ]));
    });
  });

  group('InteractionMode', () {
    test('label returns expected strings', () {
      expect(InteractionMode.code.label, 'code');
      expect(InteractionMode.architect.label, 'architect');
      expect(InteractionMode.ask.label, 'ask');
    });

    test('next cycles through all modes', () {
      expect(InteractionMode.code.next, InteractionMode.architect);
      expect(InteractionMode.architect.next, InteractionMode.ask);
      expect(InteractionMode.ask.next, InteractionMode.code);
    });

    test('full cycle returns to start', () {
      var mode = InteractionMode.code;
      for (var i = 0; i < 3; i++) {
        mode = mode.next;
      }
      expect(mode, InteractionMode.code);
    });

    test('code allows all groups', () {
      expect(InteractionMode.code.allowsGroup(ToolGroup.read), isTrue);
      expect(InteractionMode.code.allowsGroup(ToolGroup.edit), isTrue);
      expect(InteractionMode.code.allowsGroup(ToolGroup.command), isTrue);
      expect(InteractionMode.code.allowsGroup(ToolGroup.mcp), isTrue);
    });

    test('architect allows read, mcp, and edit', () {
      expect(InteractionMode.architect.allowsGroup(ToolGroup.read), isTrue);
      expect(InteractionMode.architect.allowsGroup(ToolGroup.edit), isTrue);
      expect(InteractionMode.architect.allowsGroup(ToolGroup.mcp), isTrue);
      expect(InteractionMode.architect.allowsGroup(ToolGroup.command), isFalse);
    });

    test('ask allows read and mcp only', () {
      expect(InteractionMode.ask.allowsGroup(ToolGroup.read), isTrue);
      expect(InteractionMode.ask.allowsGroup(ToolGroup.mcp), isTrue);
      expect(InteractionMode.ask.allowsGroup(ToolGroup.edit), isFalse);
      expect(InteractionMode.ask.allowsGroup(ToolGroup.command), isFalse);
    });
  });

  group('ApprovalMode', () {
    test('label returns expected strings', () {
      expect(ApprovalMode.confirm.label, 'confirm');
      expect(ApprovalMode.auto.label, 'auto');
    });

    test('toggle switches between modes', () {
      expect(ApprovalMode.confirm.toggle, ApprovalMode.auto);
      expect(ApprovalMode.auto.toggle, ApprovalMode.confirm);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cli && dart test test/config/interaction_mode_test.dart`
Expected: FAIL — file not found / import error

- [ ] **Step 3: Write minimal implementation**

```dart
// cli/lib/src/config/interaction_mode.dart

/// Which group a tool belongs to for mode-based filtering.
enum ToolGroup {
  /// Read-only, side-effect-free tools (read_file, grep, list_directory, etc.).
  read,

  /// Tools that create or modify files (write_file, edit_file).
  edit,

  /// Tools that execute shell commands (bash).
  command,

  /// External integrations (MCP tools, web_search, web_browser).
  mcp,
}

/// Interaction mode controlling which tool groups the LLM can access.
///
/// Copied from the Roo Code / Kilo Code tool-group model.
enum InteractionMode {
  /// All tools available. Default mode.
  code,

  /// Read + MCP + edit (.md files only). For planning and research.
  architect,

  /// Read + MCP only. No changes at all.
  ask,
}

/// Convenience helpers for [InteractionMode].
extension InteractionModeExt on InteractionMode {
  /// Short label shown in the status bar.
  String get label => name;

  /// The next mode in the Shift+Tab cycle.
  InteractionMode get next => switch (this) {
        InteractionMode.code => InteractionMode.architect,
        InteractionMode.architect => InteractionMode.ask,
        InteractionMode.ask => InteractionMode.code,
      };

  /// Whether this mode allows a given tool group.
  bool allowsGroup(ToolGroup group) => switch (this) {
        InteractionMode.code => true,
        InteractionMode.architect => group != ToolGroup.command,
        InteractionMode.ask =>
          group == ToolGroup.read || group == ToolGroup.mcp,
      };
}

/// Approval mode controlling whether tool calls require user confirmation.
///
/// Orthogonal to [InteractionMode].
enum ApprovalMode {
  /// Ask before untrusted tool calls.
  confirm,

  /// Auto-approve everything.
  auto,
}

/// Convenience helpers for [ApprovalMode].
extension ApprovalModeExt on ApprovalMode {
  /// Short label shown in the status bar.
  String get label => name;

  /// Toggle between confirm and auto.
  ApprovalMode get toggle => switch (this) {
        ApprovalMode.confirm => ApprovalMode.auto,
        ApprovalMode.auto => ApprovalMode.confirm,
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd cli && dart test test/config/interaction_mode_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd cli && git add lib/src/config/interaction_mode.dart test/config/interaction_mode_test.dart
git commit -m "feat: add InteractionMode, ApprovalMode, and ToolGroup enums"
```

---

### Task 2: Add ToolGroup to Tool base class

**Files:**
- Modify: `cli/lib/src/agent/tools.dart`
- Modify: `cli/test/agent/tool_trust_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `cli/test/agent/tool_trust_test.dart` (or create if needed):

```dart
import 'package:test/test.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/interaction_mode.dart';

void main() {
  group('Tool.group', () {
    test('ReadFileTool is read group', () {
      expect(ReadFileTool().group, ToolGroup.read);
    });

    test('WriteFileTool is edit group', () {
      expect(WriteFileTool().group, ToolGroup.edit);
    });

    test('EditFileTool is edit group', () {
      expect(EditFileTool().group, ToolGroup.edit);
    });

    test('BashTool is command group', () {
      final tool = BashTool(/* stub executor needed */);
      expect(tool.group, ToolGroup.command);
    });

    test('GrepTool is read group', () {
      expect(GrepTool().group, ToolGroup.read);
    });

    test('ListDirectoryTool is read group', () {
      expect(ListDirectoryTool().group, ToolGroup.read);
    });

    test('default group is read', () {
      // Tool base defaults to ToolGroup.read (safe tools)
      expect(ReadFileTool().group, ToolGroup.read);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cli && dart test test/agent/tool_trust_test.dart`
Expected: FAIL — `Tool` has no `group` getter

- [ ] **Step 3: Add `group` getter to Tool and tag built-in tools**

In `cli/lib/src/agent/tools.dart`:

Add import at top:
```dart
import 'package:glue/src/config/interaction_mode.dart';
```

Add to `Tool` abstract class (after `isMutating`):
```dart
  /// The tool group for mode-based filtering. Defaults to [ToolGroup.read].
  ToolGroup get group => switch (trust) {
        ToolTrust.safe => ToolGroup.read,
        ToolTrust.fileEdit => ToolGroup.edit,
        ToolTrust.command => ToolGroup.command,
      };
```

Add to `ForwardingTool`:
```dart
  @override
  ToolGroup get group => inner.group;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd cli && dart test test/agent/tool_trust_test.dart`
Expected: PASS

- [ ] **Step 5: Run all tests to check nothing broke**

Run: `cd cli && dart test`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
cd cli && git add lib/src/agent/tools.dart test/agent/tool_trust_test.dart
git commit -m "feat: add ToolGroup to Tool base class derived from ToolTrust"
```

---

### Task 3: Tag non-builtin tools with correct groups

**Files:**
- Check: `cli/lib/src/core/service_locator.dart` for the full tool list

The tools registered in `service_locator.dart`:
- `read_file` → safe → `ToolGroup.read` (automatic)
- `write_file` → fileEdit → `ToolGroup.edit` (automatic)
- `edit_file` → fileEdit → `ToolGroup.edit` (automatic)
- `bash` → command → `ToolGroup.command` (automatic)
- `grep` → safe → `ToolGroup.read` (automatic)
- `list_directory` → safe → `ToolGroup.read` (automatic)
- `web_search` → safe → but should be `ToolGroup.mcp`
- `web_browser` → safe → but should be `ToolGroup.mcp`
- `skill` → safe → `ToolGroup.read` (correct, always available)
- `spawn_subagent` → safe → `ToolGroup.read` (should remain available)
- `spawn_parallel_subagents` → safe → `ToolGroup.read` (should remain available)

- [ ] **Step 1: Override `group` on WebSearchTool and WebBrowserTool**

Find these tool classes and add:
```dart
@override
ToolGroup get group => ToolGroup.mcp;
```

- [ ] **Step 2: Run all tests**

Run: `cd cli && dart test`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
cd cli && git add -A
git commit -m "feat: tag web tools with ToolGroup.mcp"
```

---

## Chunk 2: Replace PermissionMode with InteractionMode + ApprovalMode

### Task 4: Rewrite PermissionGate

**Files:**
- Modify: `cli/lib/src/orchestrator/permission_gate.dart`
- Modify: `cli/test/orchestrator/permission_gate_test.dart`

- [ ] **Step 1: Rewrite the test file**

```dart
// cli/test/orchestrator/permission_gate_test.dart
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/content_part.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/interaction_mode.dart';
import 'package:glue/src/orchestrator/permission_gate.dart';
import 'package:test/test.dart';

class _StubTool extends Tool {
  final String _name;
  final ToolTrust _trust;
  final ToolGroup? _groupOverride;

  _StubTool(this._name, this._trust, [this._groupOverride]);

  @override
  String get name => _name;
  @override
  String get description => 'stub';
  @override
  List<ToolParameter> get parameters => const [];
  @override
  Future<List<ContentPart>> execute(Map<String, dynamic> args) async =>
      [const TextPart('ok')];
  @override
  ToolTrust get trust => _trust;
  @override
  ToolGroup get group => _groupOverride ?? super.group;
}

void main() {
  final tools = <String, Tool>{
    'read_file': _StubTool('read_file', ToolTrust.safe),
    'write_file': _StubTool('write_file', ToolTrust.fileEdit),
    'bash': _StubTool('bash', ToolTrust.command),
    'web_search': _StubTool('web_search', ToolTrust.safe, ToolGroup.mcp),
  };

  group('code mode + confirm approval', () {
    final gate = PermissionGate(
      interactionMode: InteractionMode.code,
      approvalMode: ApprovalMode.confirm,
      trustedTools: const {'read_file'},
      tools: tools,
      cwd: '/tmp/project',
    );

    test('allows trusted tools', () {
      final call = ToolCall(id: '1', name: 'read_file', arguments: const {'path': 'a.txt'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });

    test('asks for untrusted mutating tools', () {
      final call = ToolCall(id: '2', name: 'bash', arguments: const {'command': 'ls'});
      expect(gate.resolve(call), PermissionDecision.ask);
    });
  });

  group('code mode + auto approval', () {
    final gate = PermissionGate(
      interactionMode: InteractionMode.code,
      approvalMode: ApprovalMode.auto,
      trustedTools: const {},
      tools: tools,
      cwd: '/tmp/project',
    );

    test('allows everything', () {
      final call = ToolCall(id: '1', name: 'bash', arguments: const {'command': 'rm -rf /'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });
  });

  group('ask mode', () {
    final gate = PermissionGate(
      interactionMode: InteractionMode.ask,
      approvalMode: ApprovalMode.confirm,
      trustedTools: const {},
      tools: tools,
      cwd: '/tmp/project',
    );

    test('allows read tools', () {
      final call = ToolCall(id: '1', name: 'read_file', arguments: const {'path': 'a.txt'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });

    test('denies edit tools', () {
      final call = ToolCall(id: '2', name: 'write_file', arguments: const {'path': 'a.txt', 'content': 'x'});
      expect(gate.resolve(call), PermissionDecision.deny);
    });

    test('denies command tools', () {
      final call = ToolCall(id: '3', name: 'bash', arguments: const {'command': 'ls'});
      expect(gate.resolve(call), PermissionDecision.deny);
    });

    test('allows mcp tools', () {
      final call = ToolCall(id: '4', name: 'web_search', arguments: const {'query': 'test'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });
  });

  group('architect mode', () {
    final gate = PermissionGate(
      interactionMode: InteractionMode.architect,
      approvalMode: ApprovalMode.confirm,
      trustedTools: const {},
      tools: tools,
      cwd: '/tmp/project',
    );

    test('allows read tools', () {
      final call = ToolCall(id: '1', name: 'read_file', arguments: const {'path': 'a.txt'});
      expect(gate.resolve(call), PermissionDecision.allow);
    });

    test('denies command tools', () {
      final call = ToolCall(id: '2', name: 'bash', arguments: const {'command': 'ls'});
      expect(gate.resolve(call), PermissionDecision.deny);
    });

    test('allows edit tools targeting .md files', () {
      final call = ToolCall(id: '3', name: 'write_file', arguments: const {'path': 'plan.md', 'content': '# Plan'});
      expect(gate.resolve(call), PermissionDecision.ask); // still needs approval unless auto
    });

    test('denies edit tools targeting non-.md files', () {
      final call = ToolCall(id: '4', name: 'write_file', arguments: const {'path': 'main.dart', 'content': 'void main() {}'});
      expect(gate.resolve(call), PermissionDecision.deny);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cli && dart test test/orchestrator/permission_gate_test.dart`
Expected: FAIL — constructor signature changed

- [ ] **Step 3: Rewrite PermissionGate**

```dart
// cli/lib/src/orchestrator/permission_gate.dart
import 'package:glue/src/agent/agent_core.dart';
import 'package:glue/src/agent/tools.dart';
import 'package:glue/src/config/interaction_mode.dart';
import 'package:path/path.dart' as p;

enum PermissionDecision { allow, ask, deny }

/// Pure permission decision logic for tool calls.
///
/// Combines [InteractionMode] (which tools are available) with
/// [ApprovalMode] (whether to confirm before execution).
class PermissionGate {
  final InteractionMode interactionMode;
  final ApprovalMode approvalMode;
  final Set<String> trustedTools;
  final Map<String, Tool> tools;
  final String cwd;

  const PermissionGate({
    required this.interactionMode,
    required this.approvalMode,
    required this.trustedTools,
    required this.tools,
    required this.cwd,
  });

  PermissionDecision resolve(ToolCall call) {
    final tool = tools[call.name];
    if (tool == null) return PermissionDecision.deny;

    final group = tool.group;

    // 1. Check if the interaction mode allows this tool group at all.
    if (!interactionMode.allowsGroup(group)) {
      return PermissionDecision.deny;
    }

    // 2. Architect mode: edit tools only for .md files.
    if (interactionMode == InteractionMode.architect &&
        group == ToolGroup.edit) {
      if (!_targetsMarkdownFile(call)) {
        return PermissionDecision.deny;
      }
    }

    // 3. Apply approval mode.
    if (approvalMode == ApprovalMode.auto) {
      return PermissionDecision.allow;
    }

    // confirm mode: safe tools and trusted tools auto-approve.
    if (!tool.isMutating || isTrusted(call.name)) {
      return PermissionDecision.allow;
    }

    return PermissionDecision.ask;
  }

  bool isTrusted(String toolName) => trustedTools.contains(toolName);

  bool _targetsMarkdownFile(ToolCall call) {
    final rawPath = call.arguments['path'] as String? ??
        call.arguments['file_path'] as String?;
    if (rawPath == null) return false;
    return rawPath.endsWith('.md');
  }

  bool targetsPathOutsideCwd(ToolCall call) {
    final rawPath = call.arguments['path'] as String? ??
        call.arguments['file_path'] as String?;
    if (rawPath == null) return false;
    final resolved = p.normalize(
      p.isAbsolute(rawPath) ? rawPath : p.join(cwd, rawPath),
    );
    return !p.isWithin(cwd, resolved) && resolved != cwd;
  }

  /// Whether this tool needs confirmation at ToolCallPending time.
  bool needsEarlyConfirmation(String toolName) {
    final tool = tools[toolName];
    if (tool == null) return true;

    if (!interactionMode.allowsGroup(tool.group)) return false;

    if (approvalMode == ApprovalMode.auto) return false;
    if (isTrusted(toolName)) return false;
    if (!tool.isMutating) return false;
    return true;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd cli && dart test test/orchestrator/permission_gate_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd cli && git add lib/src/orchestrator/permission_gate.dart test/orchestrator/permission_gate_test.dart
git commit -m "feat: rewrite PermissionGate for InteractionMode + ApprovalMode"
```

---

### Task 5: Update tool filter in agent_orchestration.dart

**Files:**
- Modify: `cli/lib/src/app/agent_orchestration.dart`

- [ ] **Step 1: Replace `_syncToolFilterImpl`**

Change the import from `permission_mode.dart` to `interaction_mode.dart`.

Replace the function body:

```dart
void _syncToolFilterImpl(App app) {
  final mode = app._interactionMode;
  if (mode == InteractionMode.code) {
    app.agent.toolFilter = null; // all tools available
  } else {
    app.agent.toolFilter = (tool) {
      if (!mode.allowsGroup(tool.group)) return false;
      // Architect mode: edit tools are in the list but PermissionGate
      // handles the .md restriction at call time.
      return true;
    };
  }
}
```

- [ ] **Step 2: Update tool_filter_test.dart**

Replace the readOnly test with architect and ask mode tests:

```dart
test('architect filter excludes command tools', () async {
  agent.toolFilter = (tool) => InteractionMode.architect.allowsGroup(tool.group);
  await agent.run('hello').toList();
  expect(llm.receivedToolNames, [
    unorderedEquals(['read_file', 'write_file', 'grep']),
  ]);
});

test('ask filter excludes edit and command tools', () async {
  agent.toolFilter = (tool) => InteractionMode.ask.allowsGroup(tool.group);
  await agent.run('hello').toList();
  expect(llm.receivedToolNames, [
    unorderedEquals(['read_file', 'grep']),
  ]);
});
```

- [ ] **Step 3: Run tests**

Run: `cd cli && dart test test/agent/tool_filter_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
cd cli && git add lib/src/app/agent_orchestration.dart test/agent/tool_filter_test.dart
git commit -m "feat: tool filter uses InteractionMode group-based filtering"
```

---

### Task 6: Replace PermissionMode in App class

**Files:**
- Modify: `cli/lib/src/app.dart`
- Modify: `cli/lib/src/app/terminal_event_router.dart`
- Modify: `cli/lib/src/app/render_pipeline.dart`
- Modify: `cli/lib/src/app/command_helpers.dart`
- Delete: `cli/lib/src/config/permission_mode.dart`
- Delete: `cli/test/config/permission_mode_test.dart`

- [ ] **Step 1: In `app.dart`, replace the field**

Change:
```dart
PermissionMode _permissionMode;
```
To:
```dart
InteractionMode _interactionMode;
ApprovalMode _approvalMode;
```

Update constructor default:
```dart
_interactionMode = config?.interactionMode ?? InteractionMode.code,
_approvalMode = config?.approvalMode ?? ApprovalMode.confirm {
```

Update `_permissionGate` getter:
```dart
PermissionGate get _permissionGate => PermissionGate(
      interactionMode: _interactionMode,
      approvalMode: _approvalMode,
      trustedTools: _autoApprovedTools,
      tools: agent.tools,
      cwd: _cwd,
    );
```

Update import: replace `permission_mode.dart` with `interaction_mode.dart`.

- [ ] **Step 2: In `terminal_event_router.dart`, update Shift+Tab**

Change:
```dart
if (event case KeyEvent(key: Key.shiftTab)) {
  app._permissionMode = app._permissionMode.next;
  app._syncToolFilter();
  app._render();
  return;
}
```
To:
```dart
if (event case KeyEvent(key: Key.shiftTab)) {
  app._interactionMode = app._interactionMode.next;
  app._syncToolFilter();
  app._render();
  return;
}
```

- [ ] **Step 3: In `render_pipeline.dart`, update status bar**

Change:
```dart
final permLabel = '[${app._permissionMode.label}]';
```
To:
```dart
final modeLabel = app._approvalMode == ApprovalMode.auto
    ? '[${app._interactionMode.label}·auto]'
    : '[${app._interactionMode.label}]';
```

And replace `permLabel` with `modeLabel` where it's used in `rightSegs`.

- [ ] **Step 4: In `command_helpers.dart`, update `/info` output**

Change:
```dart
buf.writeln('  Permissions:  ${app._permissionMode.label} (Shift+Tab to cycle)');
```
To:
```dart
buf.writeln('  Mode:         ${app._interactionMode.label} (Shift+Tab to cycle)');
buf.writeln('  Approval:     ${app._approvalMode.label}');
```

- [ ] **Step 5: Delete old files**

```bash
rm cli/lib/src/config/permission_mode.dart
rm cli/test/config/permission_mode_test.dart
```

- [ ] **Step 6: Update GlueConfig**

In `cli/lib/src/config/glue_config.dart`:

Replace `PermissionMode permissionMode` field with:
```dart
final InteractionMode interactionMode;
final ApprovalMode approvalMode;
```

Update constructor defaults:
```dart
this.interactionMode = InteractionMode.code,
this.approvalMode = ApprovalMode.confirm,
```

Update the config parsing to read `interaction_mode` and `approval_mode` instead of `permission_mode`.

Update import from `permission_mode.dart` to `interaction_mode.dart`.

- [ ] **Step 7: Fix any remaining imports of permission_mode.dart**

Run: `cd cli && grep -r 'permission_mode.dart' lib/ test/`
Fix each file to import `interaction_mode.dart` instead.

- [ ] **Step 8: Run dart analyze**

Run: `cd cli && dart analyze`
Expected: No errors

- [ ] **Step 9: Run all tests**

Run: `cd cli && dart test`
Expected: All pass (may need to fix test files that imported permission_mode)

- [ ] **Step 10: Commit**

```bash
cd cli && git add -A
git commit -m "feat: replace PermissionMode with InteractionMode + ApprovalMode"
```

---

## Chunk 3: Slash Commands

### Task 7: Add mode-switching slash commands

**Files:**
- Modify: `cli/lib/src/commands/builtin_commands.dart`
- Modify: `cli/lib/src/app.dart` (add callbacks)

- [ ] **Step 1: Add `/code`, `/architect`, `/ask`, `/approve` commands**

In `builtin_commands.dart`, add new callback parameters to `create()`:

```dart
required String Function(String modeName) switchMode,
required String Function() toggleApproval,
```

Add commands:

```dart
commands.register(SlashCommand(
  name: 'code',
  description: 'Switch to code mode (all tools)',
  execute: (_) => switchMode('code'),
));

commands.register(SlashCommand(
  name: 'architect',
  description: 'Switch to architect mode (read + markdown write)',
  execute: (_) => switchMode('architect'),
));

commands.register(SlashCommand(
  name: 'ask',
  description: 'Switch to ask mode (read-only)',
  execute: (_) => switchMode('ask'),
));

commands.register(SlashCommand(
  name: 'approve',
  description: 'Toggle approval mode (confirm ↔ auto)',
  execute: (_) => toggleApproval(),
));
```

- [ ] **Step 2: Wire callbacks in `app.dart`**

In `_initCommands()`, add:

```dart
switchMode: (name) {
  final mode = InteractionMode.values.firstWhere(
    (m) => m.name == name,
    orElse: () => _interactionMode,
  );
  _interactionMode = mode;
  _syncToolFilter();
  _render();
  return 'Switched to ${mode.label} mode';
},
toggleApproval: () {
  _approvalMode = _approvalMode.toggle;
  _render();
  return 'Approval: ${_approvalMode.label}';
},
```

- [ ] **Step 3: Run dart analyze**

Run: `cd cli && dart analyze`
Expected: No errors

- [ ] **Step 4: Run all tests**

Run: `cd cli && dart test`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
cd cli && git add lib/src/commands/builtin_commands.dart lib/src/app.dart
git commit -m "feat: add /code, /architect, /ask, /approve slash commands"
```

---

### Task 8: Delete the old permission_mode_approval_test.dart

**Files:**
- Check: `cli/test/permission_mode_approval_test.dart`

- [ ] **Step 1: Read the file to understand what it tests**

If it tests `PermissionMode` directly, delete it. If it tests approval logic that's still relevant, adapt it.

- [ ] **Step 2: Delete or adapt**

```bash
rm cli/test/permission_mode_approval_test.dart
```

- [ ] **Step 3: Run all tests**

Run: `cd cli && dart test`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
cd cli && git add -A
git commit -m "chore: remove obsolete permission_mode_approval_test"
```

---

## Chunk 4: Verification

### Task 9: Final verification

- [ ] **Step 1: Run dart analyze**

Run: `cd cli && dart analyze`
Expected: No errors or warnings

- [ ] **Step 2: Run full test suite**

Run: `cd cli && dart test`
Expected: All pass

- [ ] **Step 3: Verify no remaining references to PermissionMode**

Run: `cd cli && grep -r 'PermissionMode' lib/ test/`
Expected: No results (except maybe comments referencing the old system)

- [ ] **Step 4: Verify no remaining imports of permission_mode.dart**

Run: `cd cli && grep -r 'permission_mode.dart' lib/ test/`
Expected: No results

- [ ] **Step 5: Commit any final fixes**

```bash
cd cli && git add -A
git commit -m "chore: final cleanup of interaction mode migration"
```
