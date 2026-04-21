# Responsive Panels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every overlay in the Glue CLI reflow its content on terminal resize, and scale up usefully on small terminals — by replacing "format once at open-time" with a per-render `String Function(int contentWidth)` contract.

**Architecture:**

- `SelectOption` and `PanelModal` gain `.responsive(...)` constructors that take a width-aware builder instead of a static string. Existing static constructors keep working (backward compatible). `SelectPanel.render` / `PanelModal.render` call the builder with the current content width every frame; panels already re-render on `ResizeEvent`.
- `PanelFluid.resolve` gets a small-terminal fallback: when the available dimension is near the min floor, the panel fills nearly the full dimension (minus margin) instead of an awkward 40-col box on a 45-col terminal.
- A reusable `ResponsiveTable<T>` helper wraps `TableFormatter.format` as a per-width builder, so the half-dozen picker sites stop duplicating the "build rows, format table, splice into SelectOption.label" boilerplate.
- Each caller in `panel_controller.dart` migrates to the builder variants. The header row of tables becomes a width-aware `headerBuilder` too.

**Tech Stack:** Dart 3, `package:test`, existing `TableFormatter` + `ansi_utils` helpers. No new deps.

**Non-goals for this plan:**

- Markdown/block-renderer resize (`BlockRenderer`, `MarkdownRenderer`) — the survey flagged them as architectural fragility but not user-visible breakage. Out of scope; note in future follow-up.
- Autocomplete overlay micro-tweaks (`slash_autocomplete.dart` `.padRight(16)` etc.) — keep for a separate small follow-up; they already re-render per width, just with suboptimal padding constants.
- Docked panels (`skills_docked_panel.dart`, `api_key_prompt_panel.dart`, `device_code_panel.dart`) — already responsive, confirmed by survey.

---

## File Structure

**Modify:**

- `cli/lib/src/ui/panel_modal.dart` — extend `PanelFluid.resolve`; add `linesBuilder` field + `.responsive(...)` named constructor to `PanelModal`.
- `cli/lib/src/ui/select_panel.dart` — add `.responsive` constructor to `SelectOption`; add `headerBuilder` field to `SelectPanel`; change `render()` to prefer builder when present.
- `cli/lib/src/ui/model_panel_formatter.dart` — add a `ModelPanelBuilder buildModelPanel(...)` function returning a `({int initialIndex, List<String> Function(int w) rows, List<String> Function(int w) header})` record. Keep existing `formatModelPanelLines` for now (unused after migration; delete in the last task).
- `cli/lib/src/ui/panel_controller.dart` — migrate `openHelp`, `openResume`, `openHistory`, `openModel`, `openProviderPanel`, and the `/provider add` provider picker (`_openProviderAddPicker` around line 437–468).

**Create:**

- `cli/lib/src/ui/responsive_table.dart` — new `ResponsiveTable<T>` class: takes column spec + row values, exposes `headerLines(int w)` and `rowLine(int i, int w)` and `searchTextFor(int i)`. Backed by `TableFormatter.format`.

**Tests (modify / create):**

- `cli/test/ui/panel_modal_test.dart` — small-terminal `PanelFluid` behavior; `PanelModal.responsive` invokes builder per render with correct content width.
- `cli/test/ui/select_panel_test.dart` — `.responsive` option label called per width; `headerBuilder` called per width.
- `cli/test/ui/model_panel_formatter_test.dart` — new `buildModelPanel` returns different row lines at different widths.
- `cli/test/ui/responsive_table_test.dart` (new) — width shrinks columns; header re-renders per width.
- `cli/test/ui/panel_controller_test.dart` — one integration-ish check that re-rendering a model picker after width change produces different rendered content.

---

## Task 1: PanelFluid small-terminal fallback

**Why first:** one-line, unblocks perceived "cramped" layout on small windows; no callers change.

**Files:**

- Modify: `cli/lib/src/ui/panel_modal.dart:25-33`
- Test: `cli/test/ui/panel_modal_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `cli/test/ui/panel_modal_test.dart`:

```dart
group('PanelFluid small-terminal fallback', () {
  test('uses available-minus-margin when available is near the min floor', () {
    final size = PanelFluid(0.7, 40);
    // Available 42 is close to floor (40). Instead of clamping to 40,
    // the panel should fill the terminal minus a 2-col margin = 40.
    // But available 43 should give us 41 (not 40).
    expect(size.resolve(42), 40);
    expect(size.resolve(43), 41);
    expect(size.resolve(45), 43);
  });

  test('uses percent when terminal is comfortably above floor', () {
    final size = PanelFluid(0.7, 40);
    expect(size.resolve(120), 84); // 120 * 0.7
    expect(size.resolve(80), 56);  // 80 * 0.7
  });

  test('never exceeds available', () {
    final size = PanelFluid(0.7, 40);
    expect(size.resolve(20), 18); // available 20, margin 2 → 18
  });

  test('never returns less than min when terminal is much larger', () {
    final size = PanelFluid(0.2, 40);
    // 120 * 0.2 = 24, floor is 40 → 40
    expect(size.resolve(120), 40);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```sh
cd cli && dart test test/ui/panel_modal_test.dart -N 'PanelFluid small-terminal fallback' -v
```

Expected: FAIL — first assertion (`expect(size.resolve(42), 40)`) currently returns 40 (works), but the third (`expect(size.resolve(20), 18)`) currently returns 20 (off). Some may already pass.

- [ ] **Step 3: Implement**

Replace `cli/lib/src/ui/panel_modal.dart:25-33`:

```dart
class PanelFluid extends PanelSize {
  final double maxPercent;
  final int minSize;
  final int margin;
  PanelFluid(this.maxPercent, this.minSize, {this.margin = 2});

  @override
  int resolve(int available) {
    if (available <= 0) return 0;
    final percent = (available * maxPercent).floor();
    final target = max(percent, minSize);
    // Small-terminal fallback: when the floor would dominate, fill
    // (available - margin) instead of a cramped fixed-width box.
    if (target >= available - margin) {
      return max(1, available - margin);
    }
    return min(target, available);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```sh
cd cli && dart test test/ui/panel_modal_test.dart -v
```

Expected: all `PanelFluid` tests PASS.

- [ ] **Step 5: Run full UI suite — no regression**

```sh
cd cli && dart test test/ui/
```

Expected: all pass.

- [ ] **Step 6: Commit**

```sh
cd /Users/helge/code/glue
git add cli/lib/src/ui/panel_modal.dart cli/test/ui/panel_modal_test.dart
git commit -m "feat(ui): PanelFluid small-terminal fallback

When available dimension is within margin of the min floor, fill
(available - margin) instead of clamping to floor. Avoids cramped
40-col boxes on 45-col terminals."
```

---

## Task 2: SelectOption.responsive + SelectPanel renders via builder

**Files:**

- Modify: `cli/lib/src/ui/select_panel.dart:10-20, 226-227`
- Test: `cli/test/ui/select_panel_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `cli/test/ui/select_panel_test.dart`:

```dart
group('SelectOption.responsive', () {
  test('label builder is called per render with content width', () {
    final widths = <int>[];
    final panel = SelectPanel<String>(
      title: 'Pick',
      options: [
        SelectOption.responsive(
          value: 'x',
          build: (w) {
            widths.add(w);
            return 'row@$w';
          },
          searchText: 'x',
        ),
      ],
      searchEnabled: false,
    );
    panel.render(80, 20, const []);
    panel.render(60, 20, const []);
    expect(widths, isNotEmpty);
    expect(widths.first, isNot(widths.last));
  });

  test('static SelectOption still works', () async {
    final panel = SelectPanel<String>(
      title: 'Pick',
      options: const [SelectOption(value: 'a', label: 'a')],
      searchEnabled: false,
    );
    panel.handleEvent(KeyEvent(Key.enter));
    expect(await panel.selection, 'a');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```sh
cd cli && dart test test/ui/select_panel_test.dart -N 'SelectOption.responsive' -v
```

Expected: FAIL — `SelectOption.responsive` constructor not defined.

- [ ] **Step 3: Implement**

Replace `SelectOption` definition in `cli/lib/src/ui/select_panel.dart:10-20`:

```dart
class SelectOption<T> {
  final T value;
  final String Function(int contentWidth) renderLabel;
  final String searchText;

  SelectOption({
    required this.value,
    required String label,
    String? searchText,
  })  : renderLabel = ((_) => label),
        searchText = searchText ?? label;

  SelectOption.responsive({
    required this.value,
    required String Function(int contentWidth) build,
    required this.searchText,
  }) : renderLabel = build;

  /// Back-compat getter: read the current label at an assumed width.
  /// Callers that truly need a static string (tests, logs) should prefer
  /// `renderLabel(width)` explicitly.
  String get label => renderLabel(80);
}
```

Update the label read site in `render()` at `cli/lib/src/ui/select_panel.dart:270` (inside `_contentAtRow`):

```dart
if (optionPos < filtered.length) {
  final optionIndex = filtered[optionPos];
  final option = options[optionIndex];
  final selected = optionIndex == selectedGlobalIndex;
  // contentW is passed through — see Step 4.
  return (option.renderLabel(_lastContentWidth), selected);
}
```

Thread `contentW` into `_lastContentWidth`. In `SelectPanel.render(...)` (at `cli/lib/src/ui/select_panel.dart:157`), after computing `final contentW = max(1, panelW - 4);` (line 188), add:

```dart
_lastContentWidth = contentW;
```

And declare at the top of the class (near line 38):

```dart
int _lastContentWidth = 80;
```

- [ ] **Step 4: Run test to verify it passes**

```sh
cd cli && dart test test/ui/select_panel_test.dart -v
```

Expected: both new tests PASS; existing tests still PASS.

- [ ] **Step 5: Commit**

```sh
cd /Users/helge/code/glue
git add cli/lib/src/ui/select_panel.dart cli/test/ui/select_panel_test.dart
git commit -m "feat(ui): SelectOption.responsive for per-render labels

Options can now provide a String Function(int contentWidth) builder
invoked per render. Static string constructor unchanged."
```

---

## Task 3: SelectPanel.headerBuilder

**Files:**

- Modify: `cli/lib/src/ui/select_panel.dart`
- Test: `cli/test/ui/select_panel_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `select_panel_test.dart`:

```dart
test('headerBuilder is called per render', () {
  final widths = <int>[];
  final panel = SelectPanel<String>(
    title: 'Pick',
    options: const [SelectOption(value: 'a', label: 'a')],
    headerBuilder: (w) {
      widths.add(w);
      return ['HEADER@$w'];
    },
    searchEnabled: false,
  );
  panel.render(80, 20, const []);
  panel.render(50, 20, const []);
  expect(widths, [76, 46]);
});
```

- [ ] **Step 2: Run test to verify it fails**

```sh
cd cli && dart test test/ui/select_panel_test.dart -N 'headerBuilder' -v
```

Expected: FAIL — parameter doesn't exist.

- [ ] **Step 3: Implement**

In `cli/lib/src/ui/select_panel.dart`:

Add field:

```dart
final List<String> Function(int contentWidth)? headerBuilder;
```

Add to constructor:

```dart
this.headerBuilder,
```

Replace `headerLines` reads in `render()` and `_contentAtRow()` with:

```dart
final effectiveHeader = headerBuilder?.call(contentW) ?? headerLines;
```

…and pass `effectiveHeader` where `headerLines` was used. Update `_contentAtRow` to take `effectiveHeader` instead of reading `this.headerLines`.

- [ ] **Step 4: Run test**

```sh
cd cli && dart test test/ui/select_panel_test.dart -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```sh
git add cli/lib/src/ui/select_panel.dart cli/test/ui/select_panel_test.dart
git commit -m "feat(ui): SelectPanel.headerBuilder for responsive headers"
```

---

## Task 4: PanelModal.responsive (linesBuilder)

**Files:**

- Modify: `cli/lib/src/ui/panel_modal.dart:146-200`
- Test: `cli/test/ui/panel_modal_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `panel_modal_test.dart`:

```dart
test('PanelModal.responsive rebuilds lines per render width', () {
  final widths = <int>[];
  final panel = PanelModal.responsive(
    title: 'HELP',
    buildLines: (w) {
      widths.add(w);
      return ['line@$w'];
    },
  );
  panel.render(80, 20, const []);
  panel.render(60, 20, const []);
  expect(widths.length, 2);
  expect(widths[0], isNot(widths[1]));
});
```

- [ ] **Step 2: Run test to verify it fails**

```sh
cd cli && dart test test/ui/panel_modal_test.dart -N 'PanelModal.responsive' -v
```

Expected: FAIL — constructor doesn't exist.

- [ ] **Step 3: Implement**

In `cli/lib/src/ui/panel_modal.dart`:

Change the field:

```dart
final List<String> Function(int contentWidth) linesBuilder;
```

Replace existing `lines` field. Add a `lines` getter for back-compat:

```dart
List<String> get lines => linesBuilder(80);
```

Default constructor now wraps the static list:

```dart
PanelModal({
  required this.title,
  required List<String> lines,
  ...
}) : linesBuilder = ((_) => lines),
     ...
```

Add:

```dart
PanelModal.responsive({
  required this.title,
  required this.linesBuilder,
  ...
}) : ...;
```

In `render()` replace `final visibleLines = lines.sublist(...)` with:

```dart
final allLines = linesBuilder(contentW);
final visibleLines = allLines.sublist(
  _scrollOffset,
  min(_scrollOffset + visibleContentH, allLines.length),
);
```

Update every other `lines.length` reference in `render()` and `handleEvent()` to use the cached `_lastLines` populated at the start of `render()`. For `handleEvent` (which doesn't have a width), use `_lastLines.length`; if never rendered, fall back to `linesBuilder(80).length`.

- [ ] **Step 4: Run test**

```sh
cd cli && dart test test/ui/panel_modal_test.dart -v
```

Expected: all PASS (including existing static-lines tests).

- [ ] **Step 5: Commit**

```sh
git add cli/lib/src/ui/panel_modal.dart cli/test/ui/panel_modal_test.dart
git commit -m "feat(ui): PanelModal.responsive for per-render content"
```

---

## Task 5: ResponsiveTable helper

**Files:**

- Create: `cli/lib/src/ui/responsive_table.dart`
- Test: `cli/test/ui/responsive_table_test.dart`

- [ ] **Step 1: Write the failing test**

Create `cli/test/ui/responsive_table_test.dart`:

```dart
import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/ui/responsive_table.dart';
import 'package:glue/src/ui/table_formatter.dart';
import 'package:test/test.dart';

void main() {
  group('ResponsiveTable', () {
    final table = ResponsiveTable<Map<String, String>>(
      columns: const [
        TableColumn(key: 'a', header: 'A'),
        TableColumn(key: 'b', header: 'B'),
      ],
      rows: [
        {'a': 'alpha', 'b': 'bravo'},
        {'a': 'gamma', 'b': 'delta'},
      ],
      getValues: (r) => r,
    );

    test('renderRow returns different lines at different widths', () {
      final wide = table.renderRow(0, 40);
      final narrow = table.renderRow(0, 12);
      expect(stripAnsi(wide).length, greaterThan(stripAnsi(narrow).length));
    });

    test('header lines adapt to width', () {
      final wide = table.renderHeader(40);
      final narrow = table.renderHeader(12);
      expect(stripAnsi(wide.first).length,
          greaterThan(stripAnsi(narrow.first).length));
    });

    test('rowCount matches input rows', () {
      expect(table.rowCount, 2);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```sh
cd cli && dart test test/ui/responsive_table_test.dart
```

Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

Create `cli/lib/src/ui/responsive_table.dart`:

```dart
import 'package:glue/src/ui/table_formatter.dart';

/// Width-aware wrapper over [TableFormatter]. Holds rows + column spec;
/// produces header/row strings for any requested content width. Cheap:
/// format() is re-invoked per width, but caches the last result so
/// consecutive same-width queries reuse.
class ResponsiveTable<T> {
  ResponsiveTable({
    required this.columns,
    required List<T> rows,
    required Map<String, String> Function(T row) getValues,
    this.gap = '  ',
    this.includeDivider = true,
  })  : _rows = rows.map(getValues).toList(growable: false),
        _sources = List<T>.from(rows, growable: false);

  final List<TableColumn> columns;
  final List<Map<String, String>> _rows;
  final List<T> _sources;
  final String gap;
  final bool includeDivider;

  int? _cachedWidth;
  TableRender? _cached;

  int get rowCount => _rows.length;
  T sourceAt(int i) => _sources[i];

  TableRender _renderAt(int width) {
    if (_cachedWidth == width && _cached != null) return _cached!;
    _cached = TableFormatter.format(
      columns: columns,
      rows: _rows,
      gap: gap,
      maxTotalWidth: width,
      includeHeader: true,
      includeHeaderInWidth: false,
      includeDivider: includeDivider,
    );
    _cachedWidth = width;
    return _cached!;
  }

  List<String> renderHeader(int width) => _renderAt(width).headerLines;
  String renderRow(int index, int width) => _renderAt(width).rowLines[index];
}
```

- [ ] **Step 4: Run test**

```sh
cd cli && dart test test/ui/responsive_table_test.dart -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```sh
git add cli/lib/src/ui/responsive_table.dart cli/test/ui/responsive_table_test.dart
git commit -m "feat(ui): ResponsiveTable — width-aware table renderer"
```

---

## Task 6: Migrate openModel picker

**Files:**

- Modify: `cli/lib/src/ui/panel_controller.dart:292-362`
- Modify: `cli/lib/src/ui/model_panel_formatter.dart`
- Test: `cli/test/ui/model_panel_formatter_test.dart`, `cli/test/ui/panel_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `cli/test/ui/model_panel_formatter_test.dart`:

```dart
test('buildModelPanel returns a width-aware builder', () {
  final entries = <CatalogRow>[
    (
      providerId: 'p',
      providerName: 'Provider',
      model: const ModelDef(
        id: 'm',
        name: 'Model With Fairly Long Name',
        notes: 'Note that is also long',
        capabilities: ['chat', 'tools'],
      ),
    ),
  ];
  final builder = buildModelPanel(
    entries,
    currentRef: const ModelRef(providerId: 'p', modelId: 'm'),
  );

  final wide = builder.rowLine(0, 80);
  final narrow = builder.rowLine(0, 28);

  expect(stripAnsi(wide).length, greaterThan(stripAnsi(narrow).length));
  expect(builder.initialIndex, 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

```sh
cd cli && dart test test/ui/model_panel_formatter_test.dart -N 'buildModelPanel' -v
```

Expected: FAIL — `buildModelPanel` missing.

- [ ] **Step 3: Implement the builder**

Append to `cli/lib/src/ui/model_panel_formatter.dart`:

```dart
class ModelPanelBuilder {
  ModelPanelBuilder._(this._table, this.initialIndex, this.entries);

  final ResponsiveTable<int> _table;
  final int initialIndex;
  final List<CatalogRow> entries;

  int get rowCount => entries.length;
  List<String> headerLines(int width) => _table.renderHeader(width);
  String rowLine(int index, int width) => _table.renderRow(index, width);
}

ModelPanelBuilder buildModelPanel(
  List<CatalogRow> entries, {
  required ModelRef currentRef,
}) {
  final rows = <Map<String, String>>[];
  String? lastProvider;
  var flatInitial = 0;

  for (var i = 0; i < entries.length; i++) {
    final row = entries[i];
    final isCurrent = row.providerId == currentRef.providerId &&
        row.model.id == currentRef.modelId;
    final providerHeader = row.providerId != lastProvider
        ? row.providerName.styled.cyan.toString()
        : '';
    lastProvider = row.providerId;

    if (isCurrent) flatInitial = i;

    rows.add({
      'provider': providerHeader,
      'marker': isCurrent ? '\u25cf ' : '  ',
      'name': row.model.name,
      'tag': (row.model.notes ?? '').styled.dim.toString(),
    });
  }

  final table = ResponsiveTable<int>(
    columns: const [
      TableColumn(key: 'provider', header: 'PROVIDER'),
      TableColumn(key: 'marker', header: ''),
      TableColumn(key: 'name', header: 'MODEL'),
      TableColumn(key: 'tag', header: 'NOTES'),
    ],
    rows: List<int>.generate(rows.length, (i) => i),
    getValues: (i) => rows[i],
  );

  return ModelPanelBuilder._(table, flatInitial, entries);
}
```

Add the import at the top of `model_panel_formatter.dart`:

```dart
import 'package:glue/src/ui/responsive_table.dart';
```

- [ ] **Step 4: Migrate `openModel`**

Replace `cli/lib/src/ui/panel_controller.dart:317-344` with:

```dart
final panelWidth = PanelFluid(0.8, 30);

final builder = buildModelPanel(entries, currentRef: currentRef);

final options = <SelectOption<CatalogRow>>[];
for (var i = 0; i < entries.length; i++) {
  final captured = i;
  final plain = stripAnsi(
    '${entries[i].providerName} ${entries[i].model.name} '
    '${entries[i].model.notes ?? ''}',
  );
  options.add(
    SelectOption.responsive(
      value: entries[i],
      build: (w) => builder.rowLine(captured, w),
      searchText: plain,
    ),
  );
}

final panel = SelectPanel<CatalogRow>(
  title: 'Switch Model',
  options: options,
  headerBuilder: builder.headerLines,
  searchHint: 'filter models',
  barrier: BarrierStyle.dim,
  width: panelWidth,
  height: PanelFluid(0.7, 10),
  initialIndex: builder.initialIndex,
);
```

Delete the now-unused `_contentWidthFor(panelWidth)` + `formatModelPanelLines(...)` block for this caller.

- [ ] **Step 5: Run tests**

```sh
cd cli && dart test test/ui/ -v
```

Expected: all PASS.

- [ ] **Step 6: Manual smoke**

```sh
cd cli && dart run bin/glue.dart
```

Inside: `/model` → resize terminal (drag window) → verify the table reflows (columns re-space; notes column grows/shrinks with width). Close with Esc.

- [ ] **Step 7: Commit**

```sh
git add cli/lib/src/ui/model_panel_formatter.dart cli/lib/src/ui/panel_controller.dart cli/test/ui/model_panel_formatter_test.dart
git commit -m "refactor(ui): model picker reflows on resize via ResponsiveTable"
```

---

## Task 7: Migrate openResume

**Files:**

- Modify: `cli/lib/src/ui/panel_controller.dart:127-215`

- [ ] **Step 1: Replace the body of openResume**

Replace `cli/lib/src/ui/panel_controller.dart:140-199` with:

```dart
final panelWidth = PanelFluid(0.8, 40);

final table = ResponsiveTable<SessionMeta>(
  columns: const [
    TableColumn(key: 'fork', header: 'FORK', maxWidth: 4),
    TableColumn(key: 'id', header: 'ID', maxWidth: 24),
    TableColumn(key: 'model', header: 'MODEL', maxWidth: 22),
    TableColumn(key: 'dir', header: 'DIRECTORY', maxWidth: 36),
    TableColumn(
      key: 'age',
      header: 'AGE',
      align: TableAlign.right,
      maxWidth: 10,
    ),
  ],
  gap: ' ',
  rows: sessions,
  getValues: (s) => {
    'fork': s.forkedFrom != null ? '[F]'.styled.cyan.toString() : '',
    'id': (s.title ?? s.id).styled.cyan.toString(),
    'model': s.modelRef,
    'dir': shortenPath(s.cwd).styled.dim.toString(),
    'age': timeAgo(s.startTime).styled.dim.toString(),
  },
);

final options = <SelectOption<SessionMeta>>[];
for (var i = 0; i < sessions.length; i++) {
  final s = sessions[i];
  final captured = i;
  options.add(
    SelectOption.responsive(
      value: s,
      build: (w) => table.renderRow(captured, w),
      searchText:
          '${s.title ?? s.id} ${s.modelRef} ${s.cwd} ${s.forkedFrom ?? ''}',
    ),
  );
}

final panel = SelectPanel<SessionMeta>(
  title: 'Resume Session',
  options: options,
  headerBuilder: table.renderHeader,
  searchHint: 'filter sessions',
  emptyText: 'No matching sessions.',
  barrier: BarrierStyle.dim,
  width: panelWidth,
  height: PanelFluid(0.7, 10),
);
```

- [ ] **Step 2: Verify analyze + tests**

```sh
cd cli && dart analyze --fatal-infos && dart test test/ui/
```

Expected: clean + pass.

- [ ] **Step 3: Commit**

```sh
git add cli/lib/src/ui/panel_controller.dart
git commit -m "refactor(ui): openResume reflows on resize"
```

---

## Task 8: Migrate openHistory

**Files:**

- Modify: `cli/lib/src/ui/panel_controller.dart:217-290`

- [ ] **Step 1: Apply same pattern**

Replace `openHistory`'s table-build block (lines ~228-266) with a `ResponsiveTable<HistoryEntry>` + `SelectOption.responsive` + `headerBuilder` migration analogous to Task 7. Use the columns already defined inline.

- [ ] **Step 2: Run tests**

```sh
cd cli && dart analyze --fatal-infos && dart test test/ui/
```

Expected: clean + pass.

- [ ] **Step 3: Commit**

```sh
git add cli/lib/src/ui/panel_controller.dart
git commit -m "refactor(ui): openHistory reflows on resize"
```

---

## Task 9: Migrate /provider list + /provider add pickers

**Files:**

- Modify: `cli/lib/src/ui/panel_controller.dart:437-468` (`/provider add` picker) and `:537-587` (`openProviderPanel`)

- [ ] **Step 1: Replace hardcoded `.padRight(...)` label with a ResponsiveTable**

Both places build `SelectOption<ProviderDef>` with `'${p.name.padRight(N)}  ${p.id.styled.dim.padRight(M)}  ...'` strings. Convert each to:

```dart
final table = ResponsiveTable<ProviderDef>(
  columns: const [
    TableColumn(key: 'name', header: 'PROVIDER', maxWidth: 24),
    TableColumn(key: 'id', header: 'ID', maxWidth: 14),
    TableColumn(key: 'status', header: 'STATUS', maxWidth: 12),
  ],
  rows: providers,
  getValues: (p) => {
    'name': p.name,
    'id': p.id.styled.dim.toString(),
    'status': _statusLabel(p, config).styled.dim.toString(),
  },
);
```

Then build `SelectOption.responsive(..., build: (w) => table.renderRow(i, w), searchText: ...)`.

For the `openProviderPanel` case, also pass `headerBuilder: table.renderHeader`. The `/provider add` picker currently has no header; decide whether to add one (optional).

- [ ] **Step 2: Run tests**

```sh
cd cli && dart analyze --fatal-infos && dart test test/ui/
```

- [ ] **Step 3: Commit**

```sh
git add cli/lib/src/ui/panel_controller.dart
git commit -m "refactor(ui): /provider list + /provider add reflow on resize"
```

---

## Task 10: Migrate openHelp

**Files:**

- Modify: `cli/lib/src/ui/panel_controller.dart:73-125`

- [ ] **Step 1: Convert lines[] to linesBuilder**

Replace the static `final lines = <String>[]; lines.add(...)` sequence with a function that takes `contentWidth` and returns the line list — laying out each keybinding row as `key.padRight(N)` where `N = min(18, contentWidth ~/ 3)` so that on narrow terminals the key column shrinks gracefully.

Then switch:

```dart
final panel = PanelModal(
  title: 'HELP',
  lines: lines,
  ...
);
```

to:

```dart
final panel = PanelModal.responsive(
  title: 'HELP',
  buildLines: (w) => _buildHelpLines(commands, w),
  barrier: BarrierStyle.dim,
  height: PanelFluid(0.6, 10),
);
```

Extract `_buildHelpLines(List<SlashCommand> commands, int w)` as a private method in `PanelController` (or a top-level function in the same file).

- [ ] **Step 2: Write a test**

Append to `test/ui/panel_controller_test.dart`:

```dart
test('help panel rebuilds lines per width', () {
  final wide = _buildHelpLinesForTest([], 80);
  final narrow = _buildHelpLinesForTest([], 30);
  // Wide help panel should have wider key column: more trailing spaces
  // before the description.
  expect(wide.any((l) => l.contains('                ')), isTrue);
  expect(narrow.any((l) => l.contains('                ')), isFalse);
});
```

…where `_buildHelpLinesForTest` re-exports the private function via a `@visibleForTesting` annotation, OR the function is moved to top-level and imported directly.

- [ ] **Step 3: Run tests**

```sh
cd cli && dart analyze --fatal-infos && dart test test/ui/
```

- [ ] **Step 4: Commit**

```sh
git add cli/lib/src/ui/panel_controller.dart cli/test/ui/panel_controller_test.dart
git commit -m "refactor(ui): help panel reflows on resize"
```

---

## Task 11: Delete the old `formatModelPanelLines` + unused helpers

**Files:**

- Modify: `cli/lib/src/ui/model_panel_formatter.dart`, `cli/lib/src/ui/panel_controller.dart`

- [ ] **Step 1: Verify nothing still calls formatModelPanelLines**

```sh
cd cli && rg 'formatModelPanelLines' --type dart
```

Expected: zero matches in `lib/` after Task 6.

- [ ] **Step 2: Verify \_contentWidthFor has no callers**

```sh
cd cli && rg '_contentWidthFor' --type dart
```

Expected: zero matches outside its own declaration after Tasks 6–9.

- [ ] **Step 3: Delete them**

Remove `formatModelPanelLines` function + `ModelPanelLines` class from `model_panel_formatter.dart`. Remove `_contentWidthFor` from `panel_controller.dart`. Remove any now-dead imports (`table_formatter.dart` import from panel_controller if not otherwise used — probably still needed via ResponsiveTable constructors).

- [ ] **Step 4: Run analyze + tests**

```sh
cd cli && dart analyze --fatal-infos && dart test
```

- [ ] **Step 5: Commit**

```sh
git add cli/lib/src/ui/model_panel_formatter.dart cli/lib/src/ui/panel_controller.dart
git commit -m "chore(ui): remove obsolete formatModelPanelLines + _contentWidthFor"
```

---

## Task 12: Manual verification matrix

- [ ] **Step 1: Run Glue in a wide terminal (≥120 cols)**

```sh
cd cli && dart run bin/glue.dart
```

Exercise: `/model`, `/models`, `/provider`, `/provider add`, `/history`, `/resume`, `/help`. Shrink the terminal below 80 cols while each picker is open; verify content reflows (not truncated from a wider-window layout).

- [ ] **Step 2: Run Glue in a tiny terminal (45×14)**

Resize terminal to ~45 cols × 14 rows before launching. Open `/model`. Verify the picker fills almost the whole terminal (the `PanelFluid` small-terminal fallback) instead of being a cramped 40-col box floating in a 45-col window.

- [ ] **Step 3: No regression in full test suite**

```sh
cd cli && dart format --set-exit-if-changed . && dart analyze --fatal-infos && dart test
```

Expected: all green (Docker executor test is known-flaky without a Docker daemon; document in the PR if it fails).

- [ ] **Step 4: Update Backlog**

Append a line to `TASK-22.8`'s finalSummary noting that UI responsiveness in pickers was shipped as part of the follow-up. Create a new backlog task `TASK-30 — Responsive BlockRenderer/MarkdownRenderer on resize` for the deferred renderer issue noted in this plan's non-goals, so the survey finding isn't lost.

---

## Self-Review Checklist

- **Spec coverage:** every baked-content site identified in the survey (help, resume, history, model, provider list, provider add) has a dedicated task. `PanelFluid` sizing is Task 1. `SelectOption` / `SelectPanel` / `PanelModal` API lifts are Tasks 2–4. Helper is Task 5. Cleanup is Task 11.
- **Deferred work:** autocomplete `.padRight(16)` (minor), `BlockRenderer` / `MarkdownRenderer` (unlikely to fire in practice) explicitly listed as non-goals. Follow-up task created in Task 12.
- **Placeholders:** every task specifies files + line numbers, shows code to write, shows commands to run, gives expected results.
- **Types consistency:** `String Function(int contentWidth)` used uniformly for labels and header builders. `List<String> Function(int contentWidth)` for panel lines. `ResponsiveTable.renderRow(int, int)` / `.renderHeader(int)` used identically across callers.

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-04-19-responsive-panels.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
