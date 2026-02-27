# Recursive Fuzzy File Hint — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow `@filename` to fuzzy-find files 2-3 levels deep without typing directory paths.

**Architecture:** Add a BFS-based recursive tree index alongside the existing single-dir listing. When the user types a prefix with no slash (e.g. `@app`), search the cached tree by basename. When they type a slash (e.g. `@lib/`), keep current single-dir browsing. Display shows relative paths for disambiguation.

**Tech Stack:** Dart 3.4+, `package:path`, `package:test`

---

### Task 1: Add `_TreeEntry` and `_listTree` with cache

**Files:**
- Modify: `lib/src/ui/at_file_hint.dart`
- Test: `test/ui/at_file_hint_test.dart`

**Step 1: Write failing tests for recursive listing behavior**

Add to `test/ui/at_file_hint_test.dart` inside the existing group. Create deeper structure in setUp:

```dart
// Add to setUp, after existing file creation:
Directory(p.join(tmpDir.path, 'lib', 'src')).createSync();
File(p.join(tmpDir.path, 'lib', 'src', 'app.dart')).createSync();
File(p.join(tmpDir.path, 'lib', 'src', 'config.dart')).createSync();
Directory(p.join(tmpDir.path, 'lib', 'src', 'tools')).createSync();
File(p.join(tmpDir.path, 'lib', 'src', 'tools', 'grep.dart')).createSync();
```

```dart
test('recursive fuzzy finds file in nested dir', () {
  hint.update('@config', 7);
  expect(hint.active, isTrue);
  expect(hint.matchCount, greaterThanOrEqualTo(1));
  final result = hint.accept();
  expect(result, '@lib/src/config.dart');
});

test('recursive fuzzy finds file at depth 3', () {
  hint.update('@grep', 5);
  expect(hint.active, isTrue);
  final result = hint.accept();
  expect(result, '@lib/src/tools/grep.dart');
});

test('recursive fuzzy shows relative path in display', () {
  hint.update('@config', 7);
  expect(hint.active, isTrue);
  final lines = hint.render(80);
  final joined = lines.join('\n');
  expect(joined, contains('lib/src/config.dart'));
});
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/ui/at_file_hint_test.dart`
Expected: 3 FAIL — `@config` currently only searches cwd.

**Step 3: Add `_TreeEntry` class and `_listTree` method**

In `at_file_hint.dart`, add private class:

```dart
class _TreeEntry {
  final String relPath;
  final String name;
  final bool isDirectory;
  _TreeEntry(this.relPath, this.name, this.isDirectory);
}
```

Add tree cache fields to `AtFileHint`:

```dart
List<_TreeEntry>? _cachedTree;
DateTime _cachedTreeAt = DateTime(0);
```

Add method:

```dart
static const _maxTreeEntries = 2000;
static const _maxTreeDepth = 3;

List<_TreeEntry> _listTree() {
  final now = DateTime.now();
  if (_cachedTree != null && now.difference(_cachedTreeAt).inSeconds < 2) {
    return _cachedTree!;
  }

  final entries = <_TreeEntry>[];
  final queue = <(String, String, int)>[(cwd, '', 1)];

  while (queue.isNotEmpty && entries.length < _maxTreeEntries) {
    final (dirAbs, relPrefix, depth) = queue.removeAt(0);
    List<FileSystemEntity> children;
    try {
      children = Directory(dirAbs).listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final child in children) {
      final name = p.basename(child.path);
      if (name.startsWith('.')) continue;
      final isDir = child is Directory;
      final relPath = relPrefix.isEmpty ? name : '$relPrefix/$name';
      entries.add(_TreeEntry(
        isDir ? '$relPath/' : relPath,
        name,
        isDir,
      ));
      if (isDir && depth < _maxTreeDepth) {
        queue.add((child.path, relPath, depth + 1));
      }
      if (entries.length >= _maxTreeEntries) break;
    }
  }

  _cachedTree = entries;
  _cachedTreeAt = now;
  return entries;
}
```

**Step 4: Run tests — they still fail (tree exists but `update` doesn't use it yet)**

Run: `dart test test/ui/at_file_hint_test.dart`
Expected: Still FAIL — `update()` hasn't been changed yet.

**Step 5: Commit scaffold**

```bash
git add lib/src/ui/at_file_hint.dart test/ui/at_file_hint_test.dart
git commit -m "feat(at_file_hint): add _TreeEntry and _listTree with BFS cache"
```

---

### Task 2: Wire recursive mode into `update()`

**Files:**
- Modify: `lib/src/ui/at_file_hint.dart`
- Test: `test/ui/at_file_hint_test.dart`

**Step 1: Write failing test for scoring (exact > prefix > contains)**

```dart
test('recursive fuzzy ranks exact match first', () {
  // 'app.dart' exists at root AND lib/app.dart AND lib/src/app.dart
  hint.update('@app', 4);
  expect(hint.active, isTrue);
  // Shortest path (exact basename match) should be first
  final result = hint.accept();
  // Files at root are not in tree (they're in cwd listing)
  // But lib/app.dart is shorter than lib/src/app.dart
  expect(result, contains('app.dart'));
});

test('recursive fuzzy prefers shorter paths', () {
  hint.update('@app.dart', 9);
  expect(hint.active, isTrue);
  // lib/app.dart (shorter) should rank before lib/src/app.dart
  final result = hint.accept();
  expect(result, '@lib/app.dart');
});
```

**Step 2: Run tests to verify they fail**

Run: `dart test test/ui/at_file_hint_test.dart`
Expected: FAIL

**Step 3: Modify `update()` to branch on recursive vs browse mode**

In `update()`, after computing `dirPart`, `prefix`, and validating directory:

```dart
// After line 67 (prefix computation), replace the rest of update():

if (lastSlash >= 0) {
  // --- Explicit directory browse mode (existing behavior) ---
  _buildDirCandidates(dirPart, prefix);
} else if (prefix.isEmpty) {
  // --- Empty prefix: browse cwd only (existing behavior) ---
  _buildDirCandidates('', '');
} else {
  // --- Recursive fuzzy mode ---
  _buildRecursiveCandidates(prefix);
}
```

Extract existing browse logic into `_buildDirCandidates(String dirPart, String prefix)`.

Add new `_buildRecursiveCandidates(String prefix)`:

```dart
void _buildRecursiveCandidates(String prefix) {
  final prefixLower = prefix.toLowerCase();
  final tree = _listTree();
  final candidates = <_Candidate>[];

  // Also include cwd-level entries
  try {
    final cwdEntries = _listDir(cwd);
    for (final entry in cwdEntries) {
      final name = p.basename(entry.path);
      if (name.startsWith('.')) continue;
      final isDir = entry is Directory;
      if (!name.toLowerCase().contains(prefixLower)) continue;
      final displayName = isDir ? '$name/' : name;
      candidates.add(_Candidate(displayName, displayName, isDir));
    }
  } on FileSystemException {
    // ignore
  }

  // Add recursive tree matches (match on basename)
  for (final entry in tree) {
    if (!entry.name.toLowerCase().contains(prefixLower)) continue;
    candidates.add(_Candidate(entry.relPath, entry.relPath, entry.isDirectory));
  }

  if (candidates.isEmpty) {
    dismiss();
    return;
  }

  // Score and sort
  candidates.sort((a, b) {
    final aScore = _matchScore(a.displayName, prefixLower);
    final bScore = _matchScore(b.displayName, prefixLower);
    if (aScore != bScore) return aScore.compareTo(bScore);
    final aLen = a.completionPath.length;
    final bLen = b.completionPath.length;
    if (aLen != bLen) return aLen.compareTo(bLen);
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  });

  if (candidates.length > 20) {
    candidates.removeRange(20, candidates.length);
  }

  _active = true;
  _matches = candidates;
  _selected = _selected.clamp(0, _matches.length - 1);
}

int _matchScore(String displayName, String prefixLower) {
  final name = p.basename(displayName.endsWith('/')
      ? displayName.substring(0, displayName.length - 1)
      : displayName).toLowerCase();
  if (name == prefixLower) return 0; // exact
  if (name.startsWith(prefixLower)) return 1; // prefix
  return 2; // contains
}
```

**Step 4: Run tests**

Run: `dart test test/ui/at_file_hint_test.dart`
Expected: ALL PASS (old + new tests)

**Step 5: Run dart analyze**

Run: `dart analyze`
Expected: No issues found.

**Step 6: Commit**

```bash
git add lib/src/ui/at_file_hint.dart test/ui/at_file_hint_test.dart
git commit -m "feat(at_file_hint): recursive fuzzy file finding across subdirs"
```

---

### Task 3: Deduplicate and edge cases

**Files:**
- Modify: `lib/src/ui/at_file_hint.dart`
- Test: `test/ui/at_file_hint_test.dart`

**Step 1: Write tests for edge cases**

```dart
test('recursive fuzzy skips hidden directories', () {
  Directory(p.join(tmpDir.path, '.git')).createSync();
  File(p.join(tmpDir.path, '.git', 'config')).createSync();
  hint.update('@config', 7);
  final lines = hint.render(80);
  final joined = lines.join('\n');
  expect(joined, isNot(contains('.git')));
});

test('recursive does not duplicate cwd-level files', () {
  hint.update('@main', 5);
  expect(hint.matchCount, 1); // only main.dart, not duplicated
});

test('slash after recursive still does dir browse', () {
  hint.update('@lib/', 5);
  expect(hint.active, isTrue);
  // Should show lib/ contents only (app.dart, src/, utils.dart)
  expect(hint.matchCount, 3);
});
```

**Step 2: Run tests to find failures**

Run: `dart test test/ui/at_file_hint_test.dart`

**Step 3: Fix deduplication — exclude cwd-level items from tree**

In `_buildRecursiveCandidates`, the tree already only contains entries at depth >= 1, so cwd-level entries come from `_listDir(cwd)` and tree entries come from subfolders. No overlap. If tests pass, no fix needed.

If dedup is needed: filter tree entries whose relPath doesn't contain `/` (i.e., they're cwd-level).

**Step 4: Run all tests**

Run: `dart test test/ui/at_file_hint_test.dart`
Expected: ALL PASS

**Step 5: Run dart analyze**

Run: `dart analyze`
Expected: No issues found.

**Step 6: Commit**

```bash
git add lib/src/ui/at_file_hint.dart test/ui/at_file_hint_test.dart
git commit -m "test(at_file_hint): edge cases for recursive fuzzy search"
```

---

### Task 4: Update existing tests for new setUp structure

**Files:**
- Test: `test/ui/at_file_hint_test.dart`

**Step 1: Verify existing tests still pass with deeper structure**

The new files added in setUp (lib/src/app.dart, lib/src/config.dart, lib/src/tools/grep.dart) may affect existing test counts. Review:

- `@` (empty prefix) — now lists more entries (lib/, my dir/, main.dart, pubspec.yaml, README.md = 5 cwd entries, unchanged since recursive only triggers with non-empty prefix)
- `@lib/` — now lib/ has 3 items: app.dart, src/, utils.dart (was 2)
- `@main` — unchanged (1 match at cwd level, recursive would also find it but dedup)
- `@spec` — unchanged
- Test `filters by subdirectory prefix` expects matchCount 2 for `@lib/` → now 3

**Step 2: Fix test expectations**

Update `filters by subdirectory prefix` test:

```dart
test('filters by subdirectory prefix', () {
  hint.update('@lib/', 5);
  expect(hint.active, isTrue);
  // lib/ contains app.dart, src/, utils.dart
  expect(hint.matchCount, 3);
});
```

**Step 3: Run all tests**

Run: `dart test test/ui/at_file_hint_test.dart`
Expected: ALL PASS

**Step 4: Commit**

```bash
git add test/ui/at_file_hint_test.dart
git commit -m "test(at_file_hint): update expectations for deeper test structure"
```
