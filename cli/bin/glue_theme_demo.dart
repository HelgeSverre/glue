import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:glue/src/rendering/ansi_utils.dart';
import 'package:glue/src/rendering/block_renderer.dart';
import 'package:glue/src/terminal/terminal.dart';
import 'package:glue/src/ui/dock_manager.dart';
import 'package:glue/src/ui/docked_panel.dart';
import 'package:glue/src/ui/panel_modal.dart';
import 'package:glue/src/ui/select_panel.dart';
import 'package:glue/src/ui/table_formatter.dart';
import 'package:glue/src/ui/theme_recipes.dart';
import 'package:glue/src/ui/theme_tokens.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final app = _ThemeDemoApp();
  await app.run();
}

class _ThemeDemoApp {
  final Terminal _terminal = Terminal();
  StreamSubscription<TerminalEvent>? _sub;
  StreamSubscription<ProcessSignal>? _sigintSub;
  final Completer<void> _done = Completer<void>();
  bool _shutdownStarted = false;
  Timer? _scenarioTimer;

  GlueThemeMode _mode = GlueThemeMode.minimal;
  int _page = 0;
  int _tokenSelection = 0;
  String _lastSelection = 'none';
  bool _showSelectPreview = false;
  late SelectPanel<String> _selectPanel;

  final DockManager _dockManager = DockManager();
  late _FileBrowserDockPanel _filePanel;
  late _QuickNotepadDockPanel _notepadPanel;
  late _AgentSwitcherDockPanel _agentPanel;

  int _editorContext = 0;
  String _singleBuffer = 'summarize what changed in this PR';
  String _chatBuffer = '@cli/lib/src/app.dart explain this flow';
  String _multiBuffer = 'Refactor plan:\n1. Extract parser\n2. Add tests';
  int _scenarioScroll = 0;
  int _scenarioVisibleBlocks = 1;
  bool _scenarioPaused = false;
  bool _scenarioAutoFollow = true;

  static const int _scenarioTotalBlocks = 22;

  GlueThemeTokens get _tokens => glueThemeTokens(_mode);
  GlueRecipes get _r => GlueRecipes(_tokens);

  Future<void> run() async {
    try {
      _terminal.enableRawMode();
      _terminal.hideCursor();
      _terminal.clearScreen();
      _createSelectPanel();
      _createDockPanels();
      _startScenarioStream();
      _render();

      _sub = _terminal.events.listen(_onEvent, onError: (_) {
        if (!_done.isCompleted) _done.complete();
      });
      _sigintSub = ProcessSignal.sigint.watch().listen((_) {
        if (!_done.isCompleted) _done.complete();
      });

      await _done.future;
    } finally {
      await _shutdown();
    }
  }

  Future<void> _shutdown() async {
    if (_shutdownStarted) return;
    _shutdownStarted = true;
    _scenarioTimer?.cancel();
    await _sub?.cancel();
    await _sigintSub?.cancel();
    try {
      _terminal.write('\x1b[0m');
      _terminal.write('\x1b[?2004l');
      _terminal.showCursor();
      _terminal.resetScrollRegion();
      _terminal.clearScreen();
      _terminal.moveTo(1, 1);
      _terminal.disableRawMode();
      _terminal.dispose();
    } catch (_) {
      // Best-effort restore; terminal might already be detached.
    }
  }

  void _createDockPanels() {
    _filePanel =
        _FileBrowserDockPanel(tokensProvider: () => _tokens, visible: false);
    _notepadPanel =
        _QuickNotepadDockPanel(tokensProvider: () => _tokens, visible: false);
    _agentPanel =
        _AgentSwitcherDockPanel(tokensProvider: () => _tokens, visible: false);

    _dockManager
      ..add(_filePanel)
      ..add(_notepadPanel)
      ..add(_agentPanel);
  }

  Future<void> _onEvent(TerminalEvent event) async {
    if (_showSelectPreview) {
      if (_selectPanel.handleEvent(event)) {
        if (_selectPanel.isComplete) {
          _lastSelection = await _selectPanel.selection ?? 'none';
          _showSelectPreview = false;
          _createSelectPanel();
        }
        _render();
        return;
      }
    }

    if (event case KeyEvent(key: Key.ctrlC) || CharEvent(char: 'q')) {
      if (!_done.isCompleted) _done.complete();
      return;
    }

    if (event case KeyEvent(key: Key.tab)) {
      _page = (_page + 1) % 7;
      _render();
      return;
    }

    if (event case KeyEvent(key: Key.shiftTab)) {
      _page = (_page - 1) % 7;
      if (_page < 0) _page = 6;
      _render();
      return;
    }

    if (event case CharEvent(char: final c)
        when c == '1' ||
            c == '2' ||
            c == '3' ||
            c == '4' ||
            c == '5' ||
            c == '6' ||
            c == '7') {
      _page = int.parse(c) - 1;
      _render();
      return;
    }

    if (event case CharEvent(char: 't')) {
      _mode = _mode == GlueThemeMode.minimal
          ? GlueThemeMode.highContrast
          : GlueThemeMode.minimal;
      _render();
      return;
    }

    if (_handleDockHotkeys(event)) {
      _render();
      return;
    }

    if (_dockManager.handleEvent(event)) {
      _render();
      return;
    }

    if (_page == 4 && _handleScenarioInput(event)) {
      _render();
      return;
    }

    if (event case CharEvent(char: 's')) {
      _showSelectPreview = true;
      _render();
      return;
    }

    if (_page == 0) {
      if (event case KeyEvent(key: Key.up)) {
        _tokenSelection =
            (_tokenSelection - 1).clamp(0, _tokenNames.length - 1);
        _render();
        return;
      }
      if (event case KeyEvent(key: Key.down)) {
        _tokenSelection =
            (_tokenSelection + 1).clamp(0, _tokenNames.length - 1);
        _render();
        return;
      }
    }

    if (_page == 3) {
      if (_handleEditorInput(event)) {
        _render();
        return;
      }
    }
  }

  bool _handleDockHotkeys(TerminalEvent event) {
    switch (event) {
      case KeyEvent(key: Key.escape):
        _setDockFocus();
        return true;
      case KeyEvent(key: Key.ctrlL):
        _filePanel.visible ? _filePanel.dismiss() : _filePanel.show();
        if (_filePanel.visible) _setDockFocus(file: true);
        return true;
      case KeyEvent(key: Key.ctrlK):
        _notepadPanel.visible ? _notepadPanel.dismiss() : _notepadPanel.show();
        if (_notepadPanel.visible) _setDockFocus(note: true);
        return true;
      case KeyEvent(key: Key.ctrlE):
        _agentPanel.visible ? _agentPanel.dismiss() : _agentPanel.show();
        if (_agentPanel.visible) _setDockFocus(agent: true);
        return true;
      case CharEvent(char: 'F'):
        _filePanel.show();
        _setDockFocus(file: true);
        return true;
      case CharEvent(char: 'N'):
        _notepadPanel.show();
        _setDockFocus(note: true);
        return true;
      case CharEvent(char: 'A'):
        _agentPanel.show();
        _setDockFocus(agent: true);
        return true;
      case CharEvent(char: '0'):
        _setDockFocus();
        return true;
      case CharEvent(char: 'B'):
        _filePanel.visible ? _filePanel.dismiss() : _filePanel.show();
        return true;
      case CharEvent(char: 'G'):
        _agentPanel.visible ? _agentPanel.dismiss() : _agentPanel.show();
        return true;
      case CharEvent(char: 'C'):
        _notepadPanel.toggleCollapsed();
        return true;
      default:
        return false;
    }
  }

  bool _handleEditorInput(TerminalEvent event) {
    if (event case KeyEvent(key: Key.up)) {
      _editorContext = (_editorContext - 1).clamp(0, 2);
      return true;
    }
    if (event case KeyEvent(key: Key.down)) {
      _editorContext = (_editorContext + 1).clamp(0, 2);
      return true;
    }
    if (event case KeyEvent(key: Key.backspace)) {
      final current = _currentEditorValue();
      if (current.isNotEmpty) {
        _setCurrentEditorValue(current.substring(0, current.length - 1));
      }
      return true;
    }
    if (event case KeyEvent(key: Key.enter)) {
      if (_editorContext == 2) {
        _setCurrentEditorValue('${_currentEditorValue()}\n');
      }
      return true;
    }
    if (event case CharEvent(:final char, alt: false) when _isPrintable(char)) {
      _setCurrentEditorValue('${_currentEditorValue()}$char');
      return true;
    }
    return false;
  }

  bool _handleScenarioInput(TerminalEvent event) {
    final step = max(1, _scenarioViewportRows() ~/ 2);
    switch (event) {
      case KeyEvent(key: Key.up):
        _scenarioAutoFollow = false;
        _scenarioScroll = max(0, _scenarioScroll - 1);
        return true;
      case KeyEvent(key: Key.down):
        _scenarioScroll += 1;
        return true;
      case KeyEvent(key: Key.pageUp):
        _scenarioAutoFollow = false;
        _scenarioScroll = max(0, _scenarioScroll - step);
        return true;
      case KeyEvent(key: Key.pageDown):
        _scenarioScroll += step;
        return true;
      case KeyEvent(key: Key.home):
        _scenarioAutoFollow = false;
        _scenarioScroll = 0;
        return true;
      case KeyEvent(key: Key.end):
        _scenarioAutoFollow = true;
        _scenarioScroll = 1 << 20;
        return true;
      case CharEvent(char: 'p'):
        _scenarioPaused = !_scenarioPaused;
        if (!_scenarioPaused &&
            _scenarioVisibleBlocks >= _scenarioTotalBlocks) {
          _scenarioVisibleBlocks = 1;
        }
        _startScenarioStream();
        return true;
      case CharEvent(char: 'r'):
        _resetScenarioStream();
        return true;
      case CharEvent(char: 'f'):
        _scenarioAutoFollow = true;
        _scenarioScroll = 1 << 20;
        return true;
      default:
        return false;
    }
  }

  int _scenarioViewportRows() {
    return max(3, _terminal.rows - 4);
  }

  void _startScenarioStream() {
    _scenarioTimer?.cancel();
    _scenarioTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (_scenarioPaused) return;
      if (_scenarioVisibleBlocks < _scenarioTotalBlocks) {
        _scenarioVisibleBlocks++;
        if (_scenarioAutoFollow) _scenarioScroll = 1 << 20;
        if (_page == 4) _render();
        return;
      }
      _scenarioTimer?.cancel();
    });
  }

  void _resetScenarioStream() {
    _scenarioScroll = 0;
    _scenarioVisibleBlocks = 1;
    _scenarioPaused = false;
    _scenarioAutoFollow = true;
    _startScenarioStream();
  }

  String _currentEditorValue() {
    return switch (_editorContext) {
      0 => _singleBuffer,
      1 => _chatBuffer,
      _ => _multiBuffer,
    };
  }

  void _setCurrentEditorValue(String value) {
    switch (_editorContext) {
      case 0:
        _singleBuffer = value;
      case 1:
        _chatBuffer = value;
      case 2:
        _multiBuffer = value;
    }
  }

  bool _isPrintable(String char) {
    if (char.isEmpty) return false;
    final rune = char.runes.first;
    return rune >= 0x20 && rune != 0x7f;
  }

  void _setDockFocus(
      {bool file = false, bool note = false, bool agent = false}) {
    _filePanel.setFocus(file);
    _notepadPanel.setFocus(note);
    _agentPanel.setFocus(agent);
  }

  static const _tokenNames = <String>[
    'accent',
    'accentSubtle',
    'textPrimary',
    'textSecondary',
    'textMuted',
    'focus',
    'selection',
    'info',
    'success',
    'warning',
    'danger',
  ];

  void _createSelectPanel() {
    final options = [
      'Resume session',
      'Switch model',
      'Open skills',
      'Inspect permissions',
      'Run check suite',
    ].map((item) {
      return SelectOption<String>(
        value: item,
        label: item,
        searchText: item.toLowerCase(),
      );
    }).toList(growable: false);

    _selectPanel = SelectPanel<String>(
      title: 'Command Center Preview',
      options: options,
      searchHint: 'type to filter',
      emptyText: 'No commands match.',
      barrier: BarrierStyle.dim,
      height: PanelFluid(0.55, 10),
    );
  }

  void _render() {
    final width = _terminal.columns;
    final height = _terminal.rows;
    final content = _buildContent(height);

    var grid = List<String>.generate(
      height,
      (i) => i < content.length ? _fit(content[i], width) : ' ' * width,
    );

    if (_dockManager.visiblePanels.isNotEmpty) {
      grid = _renderDockPage(grid, width, height);
    }

    if (_showSelectPreview) {
      grid = _selectPanel.render(width, height, grid);
    }

    for (var row = 0; row < height; row++) {
      _terminal.moveTo(row + 1, 1);
      _terminal.clearLine();
      _terminal.write(grid[row]);
    }
  }

  List<String> _renderDockPage(
      List<String> contentLines, int width, int height) {
    final insets = _dockManager.resolveInsets(
      terminalColumns: width,
      terminalRows: height,
    );

    final outputTop = 1 + insets.top;
    final outputBottom = max(outputTop, height - insets.bottom);
    final outputLeft = 1 + insets.left;
    final outputRight = max(outputLeft, width - insets.right);
    final outputWidth = outputRight - outputLeft + 1;

    final grid = List<String>.generate(height, (_) => ' ' * width);
    var sourceRow = 0;
    for (var row = outputTop; row <= outputBottom; row++) {
      final raw =
          sourceRow < contentLines.length ? contentLines[sourceRow] : '';
      sourceRow++;
      final clipped = ansiTruncate(raw, outputWidth);
      final pad = ' ' * max(0, outputWidth - visibleLength(clipped));
      final line =
          '${' ' * (outputLeft - 1)}$clipped$pad${' ' * (width - outputRight)}';
      grid[row - 1] = _applyBackdropDim(_fit(line, width));
    }

    final plans = _dockManager.buildRenderPlans(
      viewport: DockViewport(
        outputTop: outputTop,
        outputBottom: outputBottom,
        outputLeft: outputLeft,
        outputRight: outputRight,
        overlayTop: height + 1,
      ),
      terminalColumns: width,
    );

    for (final plan in plans) {
      _paintRect(
        grid: grid,
        row: plan.rect.row,
        col: plan.rect.col,
        width: plan.rect.width,
        height: plan.rect.height,
        lines: plan.lines,
        termWidth: width,
      );
    }

    return grid;
  }

  void _paintRect({
    required List<String> grid,
    required int row,
    required int col,
    required int width,
    required int height,
    required List<String> lines,
    required int termWidth,
  }) {
    for (var i = 0; i < height; i++) {
      final r = row + i;
      if (r < 1 || r > grid.length) continue;
      final raw = i < lines.length ? lines[i] : '';
      final clipped = ansiTruncate(raw, width);
      final padded = '$clipped${' ' * max(0, width - visibleLength(clipped))}';
      grid[r - 1] = _spliceRow(grid[r - 1], col - 1, width, padded, termWidth);
    }
  }

  String _spliceRow(
      String bgLine, int leftCol, int panelW, String overlay, int termWidth) {
    final bgPlain = stripAnsi(bgLine).padRight(termWidth);
    final before = bgPlain.substring(0, max(0, leftCol));
    final afterStart = min(termWidth, leftCol + panelW);
    final after = bgPlain.substring(afterStart);
    return '${_applyBackdropPlain(before)}$overlay${_applyBackdropPlain(after)}';
  }

  List<String> _buildContent(int height) {
    final lines = <String>[];
    final pageTitle = switch (_page) {
      0 => 'Tokens',
      1 => 'Components',
      2 => 'Docked Panels',
      3 => 'Editor Buffers',
      4 => 'Realistic Scenario',
      5 => 'Interactions',
      _ => 'Adoption Plan',
    };

    final headerLines = <String>[];
    headerLines.add(_r.brandHeading(
      'Glue TUI Design Demo',
      subtitle:
          'mode: ${_mode.name} | page: ${_page + 1}/7 ($pageTitle) | last select: $_lastSelection',
    ));
    headerLines.add('');

    final bodyLines = <String>[];
    switch (_page) {
      case 0:
        bodyLines.addAll(_tokensPage());
      case 1:
        bodyLines.addAll(_componentsPage());
      case 2:
        bodyLines.addAll(_dockPageIntro());
      case 3:
        bodyLines.addAll(_editorBuffersPage());
      case 4:
        bodyLines.addAll(_realisticScenarioPage());
      case 5:
        bodyLines.addAll(_interactionsPage());
      case 6:
        bodyLines.addAll(_planPage());
    }

    final footerLines = <String>[
      [
        _r.keyHint('tab/shift+tab', 'switch pages'),
        _r.keyHint('1..7', 'jump page'),
        _r.keyHint('t', 'toggle theme'),
        _r.keyHint('s', 'open select preview'),
        _r.keyHint('q', 'quit'),
      ].join('  '),
      _tokens.surfaceMuted(
        ' Keep: yellow accent + circle dot. Remove: construction tape style. Prefer minimal surfaces + obvious focus. ',
      ),
    ];

    final availableBody =
        max(0, height - headerLines.length - footerLines.length);
    var scrollOffset = 0;
    if (_page == 4) {
      final maxScroll = max(0, bodyLines.length - availableBody);
      if (_scenarioAutoFollow) {
        _scenarioScroll = maxScroll;
      } else {
        _scenarioScroll = _scenarioScroll.clamp(0, maxScroll);
      }
      scrollOffset = _scenarioScroll;
    }

    lines.addAll(headerLines);
    lines.addAll(
      bodyLines.skip(scrollOffset).take(max(0, availableBody)),
    );
    while (lines.length < height - footerLines.length) {
      lines.add('');
    }

    lines.addAll(footerLines);

    return lines;
  }

  List<String> _tokensPage() {
    final lines = <String>[];
    lines.add(_r.sectionHeading('Token Preview'));
    lines.add(_tokens.textMuted(
        'Goal: intuitive hierarchy. Accent only for action/focus/brand.'));
    lines.add('');

    for (var i = 0; i < _tokenNames.length; i++) {
      final name = _tokenNames[i];
      final selected = i == _tokenSelection;
      final painted = _paintTokenSample(name, 'Sample text for $name');
      lines.add(_r.listItem(name, selected: selected, description: painted));
    }

    lines.add('');
    lines.add(_r.sectionHeading('Brand Elements'));
    lines.add('  ${_tokens.accent('${_tokens.brandDot} Circle marker')}');
    lines.add('  ${_tokens.accent('Yellow accent only for key affordances')}');
    lines.add(
        '  ${_tokens.textMuted('No tape motif + no persistent loud borders')}');
    return lines;
  }

  String _paintTokenSample(String name, String value) {
    return switch (name) {
      'accent' => _tokens.accent(value),
      'accentSubtle' => _tokens.accentSubtle(value),
      'textPrimary' => _tokens.textPrimary(value),
      'textSecondary' => _tokens.textSecondary(value),
      'textMuted' => _tokens.textMuted(value),
      'focus' => _tokens.focus(value),
      'selection' => _tokens.selection(value),
      'info' => _tokens.info(value),
      'success' => _tokens.success(value),
      'warning' => _tokens.warning(value),
      'danger' => _tokens.danger(value),
      _ => value,
    };
  }

  List<String> _componentsPage() {
    final lines = <String>[];
    lines.add(_r.sectionHeading('Shared Components'));
    lines.add(_tokens.textMuted(
        'These are the same primitives used in app panels (table + selector).'));
    lines.add('');

    final table = TableFormatter.format(
      columns: const [
        TableColumn(key: 'id', header: 'ID', maxWidth: 14),
        TableColumn(key: 'label', header: 'LABEL', maxWidth: 28),
        TableColumn(key: 'state', header: 'STATE', maxWidth: 14),
      ],
      rows: [
        {
          'id': _tokens.accent('session-1'),
          'label': 'Design token migration',
          'state': _tokens.success('READY'),
        },
        {
          'id': _tokens.accent('session-2'),
          'label': 'Command palette unification',
          'state': _tokens.warning('WIP'),
        },
        {
          'id': _tokens.accent('session-3'),
          'label': 'Legacy ANSI cleanup',
          'state': _tokens.info('PLANNED'),
        },
      ],
      includeHeader: true,
      includeHeaderInWidth: true,
    );
    lines.addAll(table.headerLines);
    lines.addAll(table.rowLines);
    lines.add('');

    lines.add(_r.sectionHeading('Badges'));
    lines.add('  ${_r.badge('PRIMARY', tone: GlueTone.accent)} '
        '${_r.badge('INFO', tone: GlueTone.info)} '
        '${_r.badge('SUCCESS', tone: GlueTone.success)} '
        '${_r.badge('WARNING', tone: GlueTone.warning)} '
        '${_r.badge('DANGER', tone: GlueTone.danger)}');
    return lines;
  }

  List<String> _dockPageIntro() {
    final lines = <String>[];
    lines.add(_r.sectionHeading('Docked Panel Playground'));
    lines.add(_tokens
        .textMuted('Panels are globally toggleable and can overlay any page.'));
    lines.add('');
    lines.add(_r.keyHint(
        'Ctrl+L / Ctrl+K / Ctrl+E', 'toggle File / Notepad / Agent panels'));
    lines.add(
        _r.keyHint('F / N / A', 'focus File browser / Notepad / Agent panel'));
    lines.add(_r.keyHint('B / G', 'legacy toggle File / Agent visibility'));
    lines.add(_r.keyHint('C', 'collapse/expand top notepad'));
    lines.add(_r.keyHint('0', 'clear focused dock panel'));
    lines.add('');
    lines.add(_tokens.textMuted('Panel-local controls:'));
    lines.add(
        '  ${_tokens.textMuted('• File browser: Up/Down, Enter, Backspace, PageUp/PageDown')}');
    lines.add(
        '  ${_tokens.textMuted('• Notepad: type text, Enter newline, Backspace delete')}');
    lines.add(
        '  ${_tokens.textMuted('• Agent panel: Up/Down/PageUp/PageDown to scroll rows')}');
    return lines;
  }

  List<String> _realisticScenarioPage() {
    final lines = <String>[];
    final renderer = BlockRenderer(max(40, _terminal.columns - 2));

    lines.add(_r.sectionHeading('Canonical Realistic Scenario'));
    lines.add(_tokens.textMuted(
        'Conversation history + expanded tool states + subagents + concurrent streaming lanes.'));
    lines.add(_tokens.textMuted(
        'Stream: ${_scenarioPaused ? 'paused' : 'running'}  steps: ${_scenarioVisibleBlocks.clamp(1, _scenarioTotalBlocks)}/$_scenarioTotalBlocks  scroll: ${_scenarioAutoFollow ? 'follow' : 'manual'}'));
    lines.add(
        _r.keyHint('up/down/pgup/pgdn/home/end', 'scroll scenario history'));
    lines.add(_r.keyHint('p / r / f', 'pause-resume / restart / follow tail'));
    lines.add('');

    void addBlock(String text) {
      lines.addAll(text.split('\n'));
      lines.add('');
    }

    var step = 0;
    var laneProgress = 0;
    bool includeStep() {
      step++;
      return step <= _scenarioVisibleBlocks;
    }

    if (includeStep()) {
      addBlock(renderer.renderUser(
          'Audit this repo for flaky tests and propose a deterministic CI rollout.'));
    }
    if (includeStep()) {
      addBlock(renderer.renderAssistant(
          'I will inspect tests, identify nondeterminism, and produce a phased fix plan.'));
    }

    if (includeStep()) {
      addBlock(renderer.renderToolCallRef(ToolCallRenderState(
        name: 'search_files',
        args: {'pattern': 'sleep\\(|DateTime.now|random'},
        phase: ToolCallPhase.done,
      )));
    }
    if (includeStep()) {
      addBlock(renderer.renderAssistant(
        'Expanded: scanning test + integration folders, excluding generated artifacts and golden snapshots.',
      ));
    }
    if (includeStep()) {
      addBlock(renderer.renderToolResult(
        'test/ui/panel_modal_test.dart:112: waitForTimeout(300)\n'
        'test/integration/ollama_e2e_test.dart:31: local service dependency',
      ));
    }

    if (includeStep()) {
      addBlock(renderer.renderToolCallRef(ToolCallRenderState(
        name: 'spawn_agent',
        args: {'task': 'analyze e2e flakiness', 'count': 3},
        phase: ToolCallPhase.running,
      )));
    }
    if (includeStep()) {
      addBlock(renderer.renderAssistant(
        'Expanded: launching 3 specialized workers (e2e, shell, docs) with shared repo context.',
      ));
    }
    if (includeStep()) {
      addBlock(renderer.renderToolCallRef(ToolCallRenderState(
        name: 'exec_command',
        args: {'cmd': 'docker ps'},
        phase: ToolCallPhase.denied,
      )));
    }
    if (includeStep()) {
      addBlock(renderer.renderToolCallRef(ToolCallRenderState(
        name: 'web_search',
        args: {'q': 'Playwright deterministic retries'},
        phase: ToolCallPhase.error,
      )));
    }

    if (includeStep()) {
      addBlock(renderer.renderError(
        'Web lookup timed out after 20s. Falling back to local docs and existing CI policies.',
      ));
    }

    if (includeStep()) {
      addBlock(renderer
          .renderSubagent('↳ [1/3] e2e-agent ▶ parse test logs (running…)'));
    }
    if (includeStep()) {
      addBlock(renderer.renderSubagent(
          '↳ [2/3] shell-agent ✓ identified 3 race conditions in cleanup hooks'));
    }
    if (includeStep()) {
      addBlock(renderer.renderSubagent(
          '↳ [3/3] docs-agent ✓ drafted CI matrix + flaky-test triage policy'));
    }

    if (includeStep()) {
      addBlock(renderer.renderAssistant(
        '''Streaming merge from multiple subagents:
- e2e: replace fixed sleeps with awaited events
- shell: isolate docker-dependent tests behind tags
- docs: add ownership + triage workflow for flaky failures''',
      ));
    }
    if (includeStep()) laneProgress = 1;
    if (includeStep()) laneProgress = 2;
    if (includeStep()) laneProgress = 3;
    if (includeStep()) laneProgress = 4;
    if (includeStep()) laneProgress = 5;
    if (includeStep()) laneProgress = 6;
    if (includeStep()) laneProgress = 7;
    if (includeStep()) laneProgress = 8;

    if (laneProgress > 0) {
      lines.add(_tokens.textMuted('Live lanes (concurrent streams):'));
      lines.addAll(_streamLane(
        title: 'e2e-agent stream',
        tone: GlueTone.info,
        rows: [
          '[00:01] opened test/ui/panel_modal_test.dart',
          if (laneProgress >= 2)
            '[00:03] replaced waitForTimeout(300) -> await modalOpen()',
          if (laneProgress >= 3) '[00:05] queued patch for review',
        ],
      ));
      lines.add('');
      lines.addAll(_streamLane(
        title: 'shell-agent stream',
        tone: GlueTone.warning,
        rows: [
          if (laneProgress >= 3) '[00:02] docker dependency detected',
          if (laneProgress >= 4) '[00:04] tagging tests as requires-docker',
          if (laneProgress >= 5) '[00:06] generated CI skip message copy',
        ],
      ));
      lines.add('');
      lines.addAll(_streamLane(
        title: 'docs-agent stream',
        tone: GlueTone.success,
        rows: [
          if (laneProgress >= 5) '[00:02] editing docs/ci/flaky-tests.md',
          if (laneProgress >= 6) '[00:04] linked ownership + escalation policy',
          if (laneProgress >= 7) '[00:06] attached rollout checklist',
        ],
      ));
      lines.add('');
    }

    if (laneProgress >= 8) {
      addBlock(renderer.renderBash(
        'dart test test/ui --reporter compact',
        '00:00 +0: loading tests\n'
            '00:03 +117: all passed\n'
            'warning: 2 integration tests skipped (requires docker)',
      ));
    }

    return lines;
  }

  List<String> _editorBuffersPage() {
    final lines = <String>[];
    lines.add(_r.sectionHeading('Editor Buffer Contexts'));
    lines.add(_tokens.textMuted(
        'Use Up/Down to switch context. Type to edit. Backspace deletes. Enter adds newline in multiline.'));
    lines.add('');

    lines.addAll(_renderEditorBox(
      title: 'Single-line Prompt',
      active: _editorContext == 0,
      lines: ['❯ $_singleBuffer'],
    ));
    lines.add('');
    lines.addAll(_renderEditorBox(
      title: 'Regular Chat Input',
      active: _editorContext == 1,
      lines: ['❯ $_chatBuffer'],
    ));
    lines.add('');
    lines.addAll(_renderEditorBox(
      title: 'Multiline Planning Buffer',
      active: _editorContext == 2,
      lines: _multiBuffer.split('\n').map((l) => '·· $l').toList(),
    ));

    return lines;
  }

  List<String> _renderEditorBox({
    required String title,
    required bool active,
    required List<String> lines,
  }) {
    const width = 84;
    final out = <String>[];
    final header = _r.borderLine(width, title: title);
    out.add(active ? _tokens.focus(header) : header);

    final maxLines = min(5, lines.length);
    for (var i = 0; i < maxLines; i++) {
      final line = active && i == maxLines - 1 ? '${lines[i]}▌' : lines[i];
      out.add(_r.panelRow(width, line));
    }
    if (maxLines < 5) {
      for (var i = maxLines; i < 5; i++) {
        out.add(_r.panelRow(width, ''));
      }
    }
    out.add(_tokens.surfaceBorder('└${'─' * (width - 2)}┘'));
    return out;
  }

  List<String> _interactionsPage() {
    final lines = <String>[];
    lines.add(_r.sectionHeading('Interaction Affordances'));
    lines.add(_tokens.textMuted(
        'Focus uses underline/inverse. Selection uses muted surface + accent text.'));
    lines.add('');

    lines.add(_r.listItem('Open command center',
        selected: true, description: 'focused row'));
    lines.add(_r.listItem('Switch model',
        selected: false, description: 'secondary row'));
    lines.add(_r.listItem('Resume session',
        selected: false, description: 'secondary row'));
    lines.add('');
    lines.add(_r.keyHint('s', 'open live SelectPanel overlay'));
    lines.add(_tokens.textMuted(
        'Minimal principle: surfaces + spacing first, color second. Borders stay quiet.'));
    return lines;
  }

  List<String> _planPage() {
    return [
      _r.sectionHeading('Recommended Rollout'),
      '',
      _r.listItem('1. Finalize tokens + recipes',
          selected: true,
          description: 'freeze role names and style boundaries'),
      _r.listItem('2. Unify overlays into command center',
          selected: false,
          description: 'slash/shell/@file -> shared source model'),
      _r.listItem('3. Apply recipes to renderers',
          selected: false,
          description: 'block/markdown/status/input style consistency'),
      _r.listItem('4. Snapshot visual scenes in CI',
          selected: false, description: 'protect token + interaction behavior'),
      '',
      _r.sectionHeading('Design Rules'),
      '  ${_tokens.accent(_tokens.brandDot)} Accent is sparse: focus, CTA, brand marker only.',
      '  ${_tokens.textMuted('• Prefer soft surfaces and whitespace over heavy framing.')} ',
      '  ${_tokens.textMuted('• Keep yellow meaningful, not ambient.')} ',
      '  ${_tokens.textMuted('• Selection/focus must stay obvious in both theme modes.')} ',
    ];
  }

  String _fit(String text, int width) {
    final truncated = ansiTruncate(text, width);
    final pad = width - visibleLength(truncated);
    return '$truncated${' ' * (pad > 0 ? pad : 0)}';
  }

  String _applyBackdropDim(String text) {
    var out = text;
    out = out.replaceAll('\x1b[0m', '\x1b[0;2;48;5;234m');
    out = out.replaceAll('\x1b[22m', '\x1b[22;2m');
    out = out.replaceAll('\x1b[49m', '\x1b[49;48;5;234m');
    return '\x1b[2;48;5;234m$out\x1b[0m';
  }

  String _applyBackdropPlain(String text) {
    if (text.isEmpty) return text;
    return '\x1b[2;38;5;244;48;5;234m$text\x1b[0m';
  }

  List<String> _streamLane({
    required String title,
    required GlueTone tone,
    required List<String> rows,
  }) {
    const width = 84;
    final out = <String>[];
    final heading = _r.borderLine(width, title: title);
    final styled = switch (tone) {
      GlueTone.accent => _tokens.accent(heading),
      GlueTone.info => _tokens.info(heading),
      GlueTone.success => _tokens.success(heading),
      GlueTone.warning => _tokens.warning(heading),
      GlueTone.danger => _tokens.danger(heading),
      GlueTone.muted => _tokens.textMuted(heading),
    };
    out.add(styled);
    for (final row in rows.take(3)) {
      out.add(_r.panelRow(width, row));
    }
    out.add(_tokens.surfaceBorder('└${'─' * (width - 2)}┘'));
    return out;
  }
}

class _FsEntry {
  final String name;
  final String fullPath;
  final bool isDirectory;

  const _FsEntry(this.name, this.fullPath, this.isDirectory);
}

class _FileBrowserDockPanel extends DockedPanel {
  final GlueThemeTokens Function() _tokensProvider;

  @override
  DockEdge edge = DockEdge.left;

  @override
  DockMode mode = DockMode.floating;

  final int _extent;
  bool _visible;
  bool _focus = false;

  String _cwd;
  final List<_FsEntry> _entries = [];
  int _selected = 0;
  int _scroll = 0;
  String _preview = '';

  _FileBrowserDockPanel({
    required GlueThemeTokens Function() tokensProvider,
    int extent = 36,
    bool visible = true,
    String? cwd,
  })  : _tokensProvider = tokensProvider,
        _extent = extent,
        _visible = visible,
        _cwd = cwd ?? Directory.current.path {
    _refresh();
  }

  @override
  int get extent => _extent;

  @override
  bool get visible => _visible;

  @override
  bool get hasFocus => _visible && _focus;

  void setFocus(bool value) {
    _focus = value;
  }

  @override
  void show() {
    _visible = true;
  }

  @override
  void dismiss() {
    _visible = false;
    _focus = false;
  }

  @override
  bool handleEvent(TerminalEvent event) {
    if (!hasFocus) return false;

    const listHeight = 8;

    switch (event) {
      case KeyEvent(key: Key.up):
        _selected = max(0, _selected - 1);
        if (_selected < _scroll) _scroll = _selected;
        return true;
      case KeyEvent(key: Key.down):
        _selected = min(max(0, _entries.length - 1), _selected + 1);
        if (_selected >= _scroll + listHeight) {
          _scroll = _selected - listHeight + 1;
        }
        return true;
      case KeyEvent(key: Key.pageUp):
        _selected = max(0, _selected - listHeight);
        _scroll = max(0, _scroll - listHeight);
        return true;
      case KeyEvent(key: Key.pageDown):
        _selected = min(max(0, _entries.length - 1), _selected + listHeight);
        _scroll =
            min(max(0, _entries.length - listHeight), _scroll + listHeight);
        return true;
      case KeyEvent(key: Key.enter):
        _activateSelection();
        return true;
      case KeyEvent(key: Key.backspace):
        _goParent();
        return true;
      default:
        return false;
    }
  }

  void _activateSelection() {
    if (_entries.isEmpty || _selected < 0 || _selected >= _entries.length) {
      return;
    }
    final entry = _entries[_selected];
    if (entry.name == '..') {
      _goParent();
      return;
    }

    if (entry.isDirectory) {
      _cwd = entry.fullPath;
      _refresh();
      return;
    }

    _preview = p.basename(entry.fullPath);
  }

  void _goParent() {
    final parent = Directory(_cwd).parent.path;
    if (parent == _cwd) return;
    _cwd = parent;
    _refresh();
  }

  void _refresh() {
    _entries.clear();

    final currentDir = Directory(_cwd);
    if (!currentDir.existsSync()) {
      _cwd = Directory.current.path;
    }

    final dir = Directory(_cwd);
    final parent = dir.parent.path;
    if (parent != _cwd) {
      _entries.add(_FsEntry('..', parent, true));
    }

    try {
      final entities = dir.listSync(followLinks: false);
      entities.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
      for (final entity in entities) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        _entries.add(_FsEntry(name, entity.path, entity is Directory));
      }
    } catch (_) {
      _preview = 'Cannot read directory';
    }

    _selected = _selected.clamp(0, max(0, _entries.length - 1));
    _scroll = _scroll.clamp(0, max(0, _entries.length - 1));
  }

  @override
  List<String> render(int width, int height) {
    final t = _tokensProvider();
    final safeWidth = max(8, width);
    final safeHeight = max(6, height);
    final border =
        renderBorder(PanelStyle.simple, safeWidth, safeHeight, 'FILES');

    final contentWidth = max(1, safeWidth - 4);
    final listHeight = max(1, safeHeight - 5);
    final maxScroll = max(0, _entries.length - listHeight);
    _scroll = _scroll.clamp(0, maxScroll);

    final lines = <String>[];
    for (var row = 0; row < safeHeight; row++) {
      if (row == 0) {
        lines.add(border.first);
        continue;
      }
      if (row == safeHeight - 1) {
        lines.add(border.last);
        continue;
      }

      final bodyRow = row - 1;
      String content;
      if (bodyRow == 0) {
        content = t.textMuted('cwd: ${p.basename(_cwd)}');
      } else if (bodyRow == 1) {
        final hint =
            _preview.isEmpty ? 'enter=open  backspace=up' : 'file: $_preview';
        content = t.textMuted(hint);
      } else {
        final idx = _scroll + bodyRow - 2;
        if (idx >= 0 && idx < _entries.length) {
          final e = _entries[idx];
          final icon = e.isDirectory ? '▸ ' : '  ';
          final name = e.isDirectory ? '${e.name}/' : e.name;
          final text = '$icon$name';
          final padded = _padAnsi(text, contentWidth);
          content =
              idx == _selected ? '\x1b[7m${stripAnsi(padded)}\x1b[27m' : padded;
        } else {
          content = '';
        }
      }

      final rowText = _padAnsi(content, contentWidth);
      lines.add('\x1b[2m│\x1b[0m $rowText \x1b[2m│\x1b[0m');
    }

    return lines;
  }

  String _padAnsi(String text, int width) {
    final truncated = ansiTruncate(text, width);
    final pad = width - visibleLength(truncated);
    return '$truncated${' ' * max(0, pad)}';
  }
}

class _QuickNotepadDockPanel extends DockedPanel {
  final GlueThemeTokens Function() _tokensProvider;

  @override
  DockEdge edge = DockEdge.top;

  @override
  DockMode mode = DockMode.floating;

  bool _visible;
  bool _focus = false;
  bool _collapsed = false;
  final int _expandedExtent;
  final int _collapsedExtent;
  String _buffer = 'scratch:\n- add searchable tables\n- align dialog columns';

  _QuickNotepadDockPanel({
    required GlueThemeTokens Function() tokensProvider,
    bool visible = true,
    int expandedExtent = 7,
    int collapsedExtent = 3,
  })  : _tokensProvider = tokensProvider,
        _visible = visible,
        _expandedExtent = expandedExtent,
        _collapsedExtent = collapsedExtent;

  @override
  int get extent => _collapsed ? _collapsedExtent : _expandedExtent;

  @override
  bool get visible => _visible;

  @override
  bool get hasFocus => _visible && _focus;

  void setFocus(bool value) {
    _focus = value;
  }

  void toggleCollapsed() {
    _collapsed = !_collapsed;
  }

  @override
  void show() {
    _visible = true;
  }

  @override
  void dismiss() {
    _visible = false;
    _focus = false;
  }

  @override
  bool handleEvent(TerminalEvent event) {
    if (!hasFocus || _collapsed) return false;

    switch (event) {
      case KeyEvent(key: Key.backspace):
        if (_buffer.isNotEmpty) {
          _buffer = _buffer.substring(0, _buffer.length - 1);
        }
        return true;
      case KeyEvent(key: Key.enter):
        _buffer = '$_buffer\n';
        return true;
      case CharEvent(:final char, alt: false):
        if (_isPrintable(char)) {
          _buffer = '$_buffer$char';
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  bool _isPrintable(String char) {
    if (char.isEmpty) return false;
    final rune = char.runes.first;
    return rune >= 0x20 && rune != 0x7f;
  }

  @override
  List<String> render(int width, int height) {
    final t = _tokensProvider();
    final safeWidth = max(8, width);
    final safeHeight = max(3, height);
    final title = _collapsed ? 'NOTEPAD (collapsed)' : 'NOTEPAD';
    final border =
        renderBorder(PanelStyle.simple, safeWidth, safeHeight, title);
    final contentWidth = max(1, safeWidth - 4);

    final lines = <String>[];
    for (var row = 0; row < safeHeight; row++) {
      if (row == 0) {
        lines.add(border.first);
        continue;
      }
      if (row == safeHeight - 1) {
        lines.add(border.last);
        continue;
      }

      final bodyRow = row - 1;
      String content;
      if (_collapsed) {
        content = bodyRow == 0 ? t.textMuted('press C to expand') : '';
      } else {
        final source = _buffer.split('\n');
        final start = max(0, source.length - (safeHeight - 2));
        final visible = source.sublist(start);
        final idx = bodyRow;
        final text = idx < visible.length ? visible[idx] : '';
        final prefix = _focus ? t.accent('● ') : t.textMuted('· ');
        content = '$prefix$text';
      }

      final rowText = _padAnsi(content, contentWidth);
      lines.add('\x1b[2m│\x1b[0m $rowText \x1b[2m│\x1b[0m');
    }

    return lines;
  }

  String _padAnsi(String text, int width) {
    final truncated = ansiTruncate(text, width);
    final pad = width - visibleLength(truncated);
    return '$truncated${' ' * max(0, pad)}';
  }
}

class _AgentRow {
  final String session;
  final String agent;
  final String state;
  final String load;

  const _AgentRow({
    required this.session,
    required this.agent,
    required this.state,
    required this.load,
  });
}

class _AgentSwitcherDockPanel extends DockedPanel {
  final GlueThemeTokens Function() _tokensProvider;

  @override
  DockEdge edge = DockEdge.right;

  @override
  DockMode mode = DockMode.floating;

  final int _extent;
  bool _visible;
  bool _focus = false;
  int _selected = 0;
  int _scroll = 0;

  final List<_AgentRow> _rows = List<_AgentRow>.generate(18, (i) {
    const states = ['planning', 'tool', 'streaming', 'idle'];
    return _AgentRow(
      session: 'sess-${(i % 6) + 1}',
      agent: 'agent-${(i + 1).toString().padLeft(2, '0')}',
      state: states[i % states.length],
      load: '${(20 + i * 4).clamp(0, 99)}%',
    );
  });

  _AgentSwitcherDockPanel({
    required GlueThemeTokens Function() tokensProvider,
    int extent = 44,
    bool visible = true,
  })  : _tokensProvider = tokensProvider,
        _extent = extent,
        _visible = visible;

  @override
  int get extent => _extent;

  @override
  bool get visible => _visible;

  @override
  bool get hasFocus => _visible && _focus;

  void setFocus(bool value) {
    _focus = value;
  }

  @override
  void show() {
    _visible = true;
  }

  @override
  void dismiss() {
    _visible = false;
    _focus = false;
  }

  @override
  bool handleEvent(TerminalEvent event) {
    if (!hasFocus) return false;

    const listHeight = 8;

    switch (event) {
      case KeyEvent(key: Key.up):
        _selected = max(0, _selected - 1);
        if (_selected < _scroll) _scroll = _selected;
        return true;
      case KeyEvent(key: Key.down):
        _selected = min(_rows.length - 1, _selected + 1);
        if (_selected >= _scroll + listHeight) {
          _scroll = _selected - listHeight + 1;
        }
        return true;
      case KeyEvent(key: Key.pageUp):
        _selected = max(0, _selected - listHeight);
        _scroll = max(0, _scroll - listHeight);
        return true;
      case KeyEvent(key: Key.pageDown):
        _selected = min(_rows.length - 1, _selected + listHeight);
        _scroll = min(max(0, _rows.length - listHeight), _scroll + listHeight);
        return true;
      default:
        return false;
    }
  }

  @override
  List<String> render(int width, int height) {
    final t = _tokensProvider();
    final safeWidth = max(12, width);
    final safeHeight = max(6, height);
    final border =
        renderBorder(PanelStyle.simple, safeWidth, safeHeight, 'AGENTS');
    final contentWidth = max(1, safeWidth - 4);

    final table = TableFormatter.format(
      columns: const [
        TableColumn(key: 'sess', header: 'SESSION', maxWidth: 8),
        TableColumn(key: 'agent', header: 'AGENT', maxWidth: 10),
        TableColumn(key: 'state', header: 'STATE', maxWidth: 10),
        TableColumn(
            key: 'load', header: 'LOAD', align: TableAlign.right, maxWidth: 5),
      ],
      rows: _rows
          .map((r) => {
                'sess': r.session,
                'agent': r.agent,
                'state': r.state,
                'load': r.load,
              })
          .toList(growable: false),
      includeHeader: true,
      includeHeaderInWidth: true,
    );

    final body = [...table.headerLines, ...table.rowLines];
    final visibleCount = max(1, safeHeight - 3);
    final maxScroll = max(0, body.length - visibleCount);
    _scroll = _scroll.clamp(0, maxScroll);

    final lines = <String>[];
    for (var row = 0; row < safeHeight; row++) {
      if (row == 0) {
        lines.add(border.first);
        continue;
      }
      if (row == safeHeight - 1) {
        lines.add(border.last);
        continue;
      }

      final idx = _scroll + row - 1;
      var content = idx < body.length ? body[idx] : '';
      content = t.textMuted(content);

      final tableRowIndex = idx - table.headerLines.length;
      if (tableRowIndex >= 0 && tableRowIndex == _selected) {
        final padded = _padAnsi(content, contentWidth);
        content = '\x1b[7m${stripAnsi(padded)}\x1b[27m';
      }

      final rowText = _padAnsi(content, contentWidth);
      lines.add('\x1b[2m│\x1b[0m $rowText \x1b[2m│\x1b[0m');
    }

    return lines;
  }

  String _padAnsi(String text, int width) {
    final truncated = ansiTruncate(text, width);
    final pad = width - visibleLength(truncated);
    return '$truncated${' ' * max(0, pad)}';
  }
}
