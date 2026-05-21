/// Transcript selection — coordinate model and gesture classification.
///
/// Selection coordinates are anchored to *blocks* (logical transcript
/// entries), not to rendered-line indices. The render pipeline rebuilds
/// `outputLines` from `_blocks` on every frame, so any (line, column)
/// coordinate becomes stale as soon as another agent event arrives or the
/// terminal resizes. A `(blockId, plainTextOffset)` pair survives both,
/// because the block's plain-text rendering is a monotonic append while
/// streaming and is regenerated deterministically on resize.
library;

/// Sentinel ids used for the two pseudo-blocks rendered above any real
/// conversation entry while the agent is streaming. When the stream
/// finalises and the buffer flushes into a real [ConversationEntry], call
/// [TranscriptSelection.rebindBlockId] so existing selections keep
/// pointing at the same text.
const String kStreamingAssistantId = '__streaming_assistant__';
const String kStreamingThinkingId = '__streaming_thinking__';

/// A position inside a transcript block.
///
/// [blockId] identifies the logical block (a `ConversationEntry.id` or
/// a streaming sentinel). [plainTextOffset] is a 0-indexed offset into
/// the block's *rendered plain text* (ANSI stripped, with the block's
/// own header/prefix decoration included, lines joined by `\n`).
class TranscriptPosition {
  final String blockId;
  final int plainTextOffset;

  const TranscriptPosition({
    required this.blockId,
    required this.plainTextOffset,
  });

  TranscriptPosition copyWith({String? blockId, int? plainTextOffset}) =>
      TranscriptPosition(
        blockId: blockId ?? this.blockId,
        plainTextOffset: plainTextOffset ?? this.plainTextOffset,
      );

  @override
  bool operator ==(Object other) =>
      other is TranscriptPosition &&
      other.blockId == blockId &&
      other.plainTextOffset == plainTextOffset;

  @override
  int get hashCode => Object.hash(blockId, plainTextOffset);

  @override
  String toString() => 'TranscriptPosition($blockId@$plainTextOffset)';
}

/// An active drag selection.
///
/// [anchor] is the mouse-down origin (resolved at drag start). [focus]
/// updates with each motion event. [start]/[end] expose the ordered pair
/// in document order, given an ordered list of block ids.
class TranscriptSelection {
  final TranscriptPosition anchor;
  final TranscriptPosition focus;

  const TranscriptSelection({required this.anchor, required this.focus});

  TranscriptSelection withFocus(TranscriptPosition focus) =>
      TranscriptSelection(anchor: anchor, focus: focus);

  /// Whether the selection covers any cells at all.
  bool get isEmpty => anchor == focus;

  /// Return a new selection where any position with [from] as its blockId
  /// is rewritten to use [to]. Used to migrate a selection across the
  /// streaming-buffer → real-entry handoff without losing the anchor.
  TranscriptSelection rebindBlockId(String from, String to) {
    final newAnchor = anchor.blockId == from
        ? anchor.copyWith(blockId: to)
        : anchor;
    final newFocus = focus.blockId == from
        ? focus.copyWith(blockId: to)
        : focus;
    if (identical(newAnchor, anchor) && identical(newFocus, focus)) {
      return this;
    }
    return TranscriptSelection(anchor: newAnchor, focus: newFocus);
  }

  /// Returns `(start, end)` ordered by document order using [blockOrder]
  /// as the canonical block sequence. Returns `null` if either endpoint's
  /// block is missing from [blockOrder] (e.g. block was removed).
  (TranscriptPosition, TranscriptPosition)? ordered(List<String> blockOrder) {
    final indexOf = <String, int>{};
    for (var i = 0; i < blockOrder.length; i++) {
      indexOf[blockOrder[i]] = i;
    }
    final ai = indexOf[anchor.blockId];
    final fi = indexOf[focus.blockId];
    if (ai == null || fi == null) return null;
    if (ai < fi) return (anchor, focus);
    if (ai > fi) return (focus, anchor);
    return anchor.plainTextOffset <= focus.plainTextOffset
        ? (anchor, focus)
        : (focus, anchor);
  }
}

/// Transient state held while the mouse button is pressed in the output
/// zone. Promotes to a real selection once the user moves the cursor more
/// than [dragThresholdCells] cells away from the origin — below that, the
/// gesture is treated as a click.
class DragState {
  final int originX;
  final int originY;
  final TranscriptPosition origin;
  bool exceededThreshold;

  DragState({
    required this.originX,
    required this.originY,
    required this.origin,
    this.exceededThreshold = false,
  });

  /// Update [exceededThreshold] given the latest motion coordinates and
  /// return whether the drag has just crossed the threshold (i.e. the
  /// caller should now treat subsequent motion as a selection update).
  bool observeMotion(int x, int y) {
    if (exceededThreshold) return false;
    final dx = (x - originX).abs();
    final dy = (y - originY).abs();
    if (dx + dy >= dragThresholdCells) {
      exceededThreshold = true;
      return true;
    }
    return false;
  }
}

/// Minimum Manhattan distance (in terminal cells) that the cursor must
/// move from the mouse-down origin before a press-hold-release gesture
/// counts as a drag rather than a click. 2 cells is small enough to feel
/// responsive but large enough that an unintentional 1-cell wobble doesn't
/// suppress click-to-expand on subagent groups.
const int dragThresholdCells = 2;

// ── Char-class word selection ──────────────────────────────────────────
//
// Mirrors the IntelliJ / token-editor model: every char in a plain-text
// line falls into exactly one of three classes. Double-click "expand to
// word" then selects the contiguous run of chars sharing the click target's
// class. The punctuation set is a near-1:1 port of
// `~/code/token-editor/src/util/text.rs:4-38` so the two tools agree on
// what a "word" means in their UIs.

/// Three-way char classification used by [findClassRange].
enum CharClass { whitespace, word, punctuation }

const Set<int> _punctuation = {
  0x2F, // /
  0x3A, // :
  0x2C, // ,
  0x2E, // .
  0x2D, // -
  0x28, // (
  0x29, // )
  0x7B, // {
  0x7D, // }
  0x5B, // [
  0x5D, // ]
  0x3B, // ;
  0x22, // "
  0x27, // '
  0x3C, // <
  0x3E, // >
  0x3D, // =
  0x2B, // +
  0x2A, // *
  0x26, // &
  0x7C, // |
  0x21, // !
  0x40, // @
  0x23, // #
  0x24, // $
  0x25, // %
  0x5E, // ^
  0x7E, // ~
  0x60, // `
  0x5C, // \
  0x3F, // ?
};

bool _isWhitespace(int rune) =>
    rune == 0x20 ||
    rune == 0x09 ||
    rune == 0x0A ||
    rune == 0x0D ||
    rune == 0xA0;

/// Classify a single Unicode code point. Whitespace and a fixed ASCII
/// punctuation set act as boundaries; everything else (Unicode letters,
/// digits, `_`, emoji, combining marks, CJK) counts as a word char.
CharClass classify(int rune) {
  if (_isWhitespace(rune)) return CharClass.whitespace;
  if (_punctuation.contains(rune)) return CharClass.punctuation;
  return CharClass.word;
}

/// Return the contiguous same-class run that contains [offset] in
/// [plain] as an end-exclusive `(start, end)` pair. Returns `(0, 0)` for
/// empty strings or offsets so far out of range there's nothing useful
/// to grab.
///
/// Walks by UTF-16 code unit (matches how `_resolvePositionAt` records
/// offsets). Surrogate pairs are handled — the high-surrogate's rune is
/// classified via the combined codepoint, and the pair stays atomic
/// because each half classifies identically when scanned individually.
(int, int) findClassRange(String plain, int offset) {
  if (plain.isEmpty) return (0, 0);
  final pivot = offset.clamp(0, plain.length - 1);
  final pivotClass = _classAt(plain, pivot);

  var start = pivot;
  while (start > 0 && _classAt(plain, start - 1) == pivotClass) {
    start--;
  }
  var end = pivot + _codeUnitLengthAt(plain, pivot);
  while (end < plain.length && _classAt(plain, end) == pivotClass) {
    end += _codeUnitLengthAt(plain, end);
  }
  return (start, end);
}

/// Classify the codepoint that *starts* at [i]. For a low surrogate
/// (we landed mid-pair), defer to the preceding high surrogate so the
/// pair classifies as one unit.
CharClass _classAt(String plain, int i) {
  final cu = plain.codeUnitAt(i);
  if (cu >= 0xDC00 && cu <= 0xDFFF && i > 0) {
    // Low surrogate — re-decode from the preceding high surrogate.
    final hi = plain.codeUnitAt(i - 1);
    if (hi >= 0xD800 && hi <= 0xDBFF) {
      final cp = 0x10000 + ((hi - 0xD800) << 10) + (cu - 0xDC00);
      return classify(cp);
    }
  }
  if (cu >= 0xD800 && cu <= 0xDBFF && i + 1 < plain.length) {
    final lo = plain.codeUnitAt(i + 1);
    if (lo >= 0xDC00 && lo <= 0xDFFF) {
      final cp = 0x10000 + ((cu - 0xD800) << 10) + (lo - 0xDC00);
      return classify(cp);
    }
  }
  return classify(cu);
}

int _codeUnitLengthAt(String plain, int i) {
  if (i >= plain.length) return 0;
  final cu = plain.codeUnitAt(i);
  if (cu >= 0xD800 && cu <= 0xDBFF && i + 1 < plain.length) {
    final lo = plain.codeUnitAt(i + 1);
    if (lo >= 0xDC00 && lo <= 0xDFFF) return 2;
  }
  return 1;
}

// ── Click chain (double / triple click) ────────────────────────────────

/// Time window inside which successive clicks at the same cell are
/// treated as a chain. Matches token-editor's
/// `runtime/mouse.rs:50` (300 ms).
const Duration clickChainWindow = Duration(milliseconds: 300);

/// Tracks consecutive mouse-up events to detect double/triple clicks.
/// Terminal mouse protocols only emit independent press/release pairs,
/// so we synthesise the chain by accumulating clicks that are both
/// rapid (within [clickChainWindow]) and at the *exact* same cell.
///
/// Returns counts in the sequence 1 → 2 → 3 → 1; subsequent clicks
/// wrap so a fourth click resets the chain.
class ClickChain {
  DateTime? _lastAt;
  int _lastX = 0;
  int _lastY = 0;
  int _count = 0;

  /// Record a click at cell [x],[y] at time [now] and return the
  /// updated count (1, 2, or 3). Any cell change OR a slow window
  /// resets the count back to 1.
  int register(int x, int y, DateTime now) {
    final last = _lastAt;
    final rapid = last != null && now.difference(last) <= clickChainWindow;
    final sameCell = x == _lastX && y == _lastY;
    _count = (rapid && sameCell && _count < 3) ? _count + 1 : 1;
    _lastAt = now;
    _lastX = x;
    _lastY = y;
    return _count;
  }

  /// Forget the chain — used when a drag or other gesture invalidates
  /// any accumulated clicks.
  void reset() {
    _count = 0;
    _lastAt = null;
  }

  /// Current count without modifying state. Mostly useful for tests.
  int get count => _count;
}
