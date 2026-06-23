import 'dart:io';
import 'dart:math';

/// Wrap [text] in an OSC 8 terminal hyperlink pointing to [url].
///
/// Modern terminals (iTerm2, Ghostty, Kitty, WezTerm, Windows Terminal)
/// render this as a clickable link. Terminals that don't support OSC 8
/// simply show the visible text — graceful degradation.
///
/// Empty [url] returns the plain display text; this avoids emitting an
/// empty OSC-8 envelope (`\x1b]8;;\x07…\x1b]8;;\x07`) that some terminals
/// would render as a visible artifact.
///
/// Protocol: \x1b]8;;URL\x07VISIBLE_TEXT\x1b]8;;\x07
String osc8Link(String url, [String? text]) {
  final display = text ?? url;
  if (url.isEmpty) return display;
  return '\x1b]8;;$url\x07$display\x1b]8;;\x07';
}

/// Wrap [path] in an OSC 8 file hyperlink using an absolute file URI while
/// preserving [text] (or the original path) as the visible label.
String osc8FileLink(String path, [String? text]) {
  if (path.isEmpty) return text ?? path;
  final absoluteUri = File(path).absolute.uri.toString();
  return osc8Link(absoluteUri, text ?? path);
}

// Bare URL detector used by terminal renderers outside the markdown pipeline.
//
// ')' is excluded to avoid swallowing trailing parens in prose like
// "(see https://example.com)". The lookbehinds avoid re-wrapping URLs already
// embedded in OSC 8 hyperlinks.
final _bareUrlPattern = RegExp(
  r'(?<!\x1b\]8;;)(?<!\x07)https?://[^\s<>\[\])`\x07\x1b'
  "'"
  r'"]+',
);

/// Convert bare http/https URLs in [text] into OSC 8 hyperlinks.
String linkifyUrls(String text) {
  return text.replaceAllMapped(_bareUrlPattern, (m) {
    var url = m.group(0)!;
    var suffix = '';
    while (url.isNotEmpty && '.,;:!?)'.contains(url[url.length - 1])) {
      suffix = url[url.length - 1] + suffix;
      url = url.substring(0, url.length - 1);
    }
    return '${osc8Link(url)}$suffix';
  });
}

// Precompiled patterns for ANSI escape sequence matching.
final _oscPattern = RegExp(r'\x1b\][^\x07]*\x07');
final _csiPattern = RegExp(r'\x1b\[[0-9;]*[a-zA-Z]');

/// One visible cell produced by [_walkCells]: the raw substring [text] that
/// renders it and its terminal column [width] (0 for zero-width marks, 2 for
/// wide glyphs).
class _Cell {
  final String text;
  final int width;
  const _Cell(this.text, this.width);
}

/// Walk [s] left-to-right, invoking [onAnsi] for each CSI/OSC escape sequence
/// (in source order) and [onCell] for each visible cell. This is the single
/// tokenizer shared by [visibleLength], [ansiTruncate], and
/// [applySelectionHighlight] so the surrogate-pair decode and escape-skipping
/// logic lives in exactly one place.
void _walkCells(
  String s, {
  void Function(String seq)? onAnsi,
  required void Function(_Cell cell) onCell,
}) {
  var i = 0;
  while (i < s.length) {
    final csiMatch = _csiPattern.matchAsPrefix(s, i);
    if (csiMatch != null) {
      final seq = csiMatch.group(0)!;
      onAnsi?.call(seq);
      i += seq.length;
      continue;
    }
    final oscMatch = _oscPattern.matchAsPrefix(s, i);
    if (oscMatch != null) {
      final seq = oscMatch.group(0)!;
      onAnsi?.call(seq);
      i += seq.length;
      continue;
    }
    final codeUnit = s.codeUnitAt(i);
    int cp;
    int advance;
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && i + 1 < s.length) {
      final low = s.codeUnitAt(i + 1);
      cp = 0x10000 + ((codeUnit - 0xD800) << 10) + (low - 0xDC00);
      advance = 2;
    } else {
      cp = codeUnit;
      advance = 1;
    }
    onCell(_Cell(s.substring(i, i + advance), charWidth(cp)));
    i += advance;
  }
}

/// Strip all ANSI escape sequences from [text],
/// including CSI sequences and OSC sequences (e.g. hyperlinks).
String stripAnsi(String text) {
  return text
      .replaceAll(_oscPattern, '') // OSC (BEL-terminated)
      .replaceAll(_csiPattern, ''); // CSI
}

/// Compute the visible column width of [text] in a terminal,
/// accounting for ANSI escapes, wide characters (emoji, CJK), and
/// zero-width characters (combining marks, variation selectors).
int visibleLength(String text) {
  var width = 0;
  _walkCells(text, onCell: (cell) => width += cell.width);
  return width;
}

/// Truncate [text] to [maxVisible] visible columns, preserving ANSI
/// sequences (both CSI and OSC) and handling wide characters.
/// Appends '…' if truncated.
String ansiTruncate(String text, int maxVisible) {
  if (maxVisible <= 0) return '';
  if (maxVisible == 1) return visibleLength(text) <= 1 ? text : '…';
  if (visibleLength(text) <= maxVisible) return text;
  final buf = StringBuffer();
  int visible = 0;
  var sawAnsi = false;
  var hasOpenOsc8 = false;
  var stopped = false;
  _walkCells(
    text,
    onAnsi: (seq) {
      // Mirror the original `while (visible < maxVisible - 1)` guard: once the
      // visible budget is exhausted, no further tokens (escapes included) are
      // emitted into the truncated output.
      if (stopped || visible >= maxVisible - 1) {
        stopped = true;
        return;
      }
      sawAnsi = true;
      if (seq.startsWith('\x1b]8;;')) {
        hasOpenOsc8 = seq != '\x1b]8;;\x07';
      }
      buf.write(seq);
    },
    onCell: (cell) {
      if (stopped || visible >= maxVisible - 1) {
        stopped = true;
        return;
      }
      if (cell.width == 0) {
        buf.write(cell.text);
        return;
      }
      if (visible + cell.width > maxVisible - 1) {
        stopped = true;
        return;
      }
      buf.write(cell.text);
      visible += cell.width;
    },
  );
  buf.write('…');
  if (hasOpenOsc8) {
    buf.write('\x1b]8;;\x07');
  }
  if (sawAnsi) {
    // Ensure truncated styled text never leaks attributes into subsequent cells.
    buf.write('\x1b[0m');
  }
  return buf.toString();
}

/// Word-wrap [text] to fit within [maxWidth] visible columns.
/// Preserves ANSI sequences and existing newlines.
///
/// ```
/// ansiWrap("The quick brown fox jumped over the lazy dog", 20)
/// →  The quick brown fox
///    jumped over the
///    lazy dog
/// ```
String ansiWrap(String text, int maxWidth) {
  if (maxWidth <= 0) return text;
  final lines = <String>[];
  for (final paragraph in text.split('\n')) {
    if (paragraph.isEmpty) {
      lines.add('');
      continue;
    }
    if (visibleLength(paragraph) <= maxWidth) {
      lines.add(paragraph);
      continue;
    }
    // Word-wrap by splitting on spaces, tracking visible width
    final words = paragraph.split(' ');
    var currentLine = StringBuffer();
    var currentWidth = 0;
    for (var w = 0; w < words.length; w++) {
      final wordWidth = visibleLength(words[w]);
      final separatorWidth = currentWidth > 0 ? 1 : 0;
      if (currentWidth + separatorWidth + wordWidth > maxWidth &&
          currentWidth > 0) {
        lines.add(currentLine.toString());
        currentLine = StringBuffer();
        currentWidth = 0;
      }
      if (currentWidth > 0) {
        currentLine.write(' ');
        currentWidth++;
      }
      currentLine.write(words[w]);
      currentWidth += wordWidth;
    }
    if (currentWidth > 0) lines.add(currentLine.toString());
  }
  return lines.join('\n');
}

/// Word-wrap [text] to [width] visible columns, prepending [firstPrefix]
/// to the first line and [nextPrefix] to continuation lines.
///
/// Unlike [ansiWrap] which only breaks long lines, this also handles
/// prefixed/indented content where continuation lines need alignment.
///
/// ```
/// // Plain indentation (firstPrefix & nextPrefix = '   '):
/// wrapIndented("The quick brown fox jumped", 20,
///     firstPrefix: '   ', nextPrefix: '   ')
/// →     The quick brown
///       fox jumped
///
/// // List bullet (firstPrefix = '• ', nextPrefix = '  '):
/// wrapIndented("The quick brown fox jumped", 20,
///     firstPrefix: '• ', nextPrefix: '  ')
/// →  • The quick brown
///      fox jumped
///
/// // Blockquote (firstPrefix & nextPrefix = '│ '):
/// wrapIndented("The quick brown fox jumped", 20,
///     firstPrefix: '│ ', nextPrefix: '│ ')
/// →  │ The quick brown
///    │ fox jumped
/// ```
String wrapIndented(
  String text,
  int width, {
  String firstPrefix = '',
  String nextPrefix = '',
}) {
  final prefixWidth = max(
    visibleLength(firstPrefix),
    visibleLength(nextPrefix),
  );
  final contentWidth = width - prefixWidth;
  if (contentWidth <= 0) return '$firstPrefix$text';
  final wrapped = ansiWrap(text, contentWidth);
  final lines = wrapped.split('\n');
  if (lines.isEmpty) return firstPrefix;
  final buf = StringBuffer(firstPrefix);
  buf.write(lines.first);
  for (var i = 1; i < lines.length; i++) {
    buf.write('\n$nextPrefix${lines[i]}');
  }
  return buf.toString();
}

/// Wrap visible columns `[startCol, endCol)` of an ANSI-styled [line] with
/// reverse-video (`\x1b[7m` / `\x1b[27m`), preserving existing CSI and OSC
/// sequences and treating wide glyphs as 2 cells.
///
/// Used to paint the transcript-selection highlight onto the visible
/// viewport slice without forcing every renderer downstream to know
/// anything about selections.
///
/// Columns count *display cells*: a CJK or emoji glyph occupies 2 cells.
/// If [startCol] falls inside a wide glyph the entire glyph is included;
/// likewise for [endCol]. Out-of-range bounds clamp to the line's
/// visible width. Returns [line] unchanged if `endCol <= startCol`.
String applySelectionHighlight(String line, int startCol, int endCol) {
  if (endCol <= startCol) return line;
  final buf = StringBuffer();
  var visible = 0;
  var inHighlight = false;

  void openIfNeeded() {
    if (!inHighlight) {
      buf.write('\x1b[7m');
      inHighlight = true;
    }
  }

  void closeIfNeeded() {
    if (inHighlight) {
      buf.write('\x1b[27m');
      inHighlight = false;
    }
  }

  _walkCells(
    line,
    onAnsi: buf.write,
    onCell: (cell) {
      // Zero-width characters (combining marks, ZWJ, etc.) attach to
      // whatever was just emitted — keep the current highlight state so
      // diacritics don't drift out of the reverse-video range.
      if (cell.width == 0) {
        buf.write(cell.text);
        return;
      }
      final cellStart = visible;
      final cellEnd = visible + cell.width;
      final inRange = cellEnd > startCol && cellStart < endCol;
      if (inRange) {
        openIfNeeded();
      } else {
        closeIfNeeded();
      }
      buf.write(cell.text);
      visible += cell.width;
    },
  );
  closeIfNeeded();
  return buf.toString();
}

/// Translate a visible column [visiblePos] into a code-unit index in [s],
/// skipping CSI escape sequences (which occupy no columns) while counting
/// every other code unit as one column.
///
/// Note: unlike [visibleLength], this counts code units (not display cells)
/// for visible characters and only skips CSI (not OSC) escapes. It exists for
/// the overlay-splice paths that slice an already-padded background row at a
/// known column, where each background cell was emitted as a single code unit.
int ansiColumnToIndex(String s, int visiblePos) {
  var visible = 0;
  var i = 0;
  while (i < s.length && visible < visiblePos) {
    final match = _csiPattern.matchAsPrefix(s, i);
    if (match != null) {
      i += match.group(0)!.length;
    } else {
      visible++;
      i++;
    }
  }
  return i;
}

/// Splice [overlay] onto [bgLine] at visible column [leftCol], occupying
/// [panelW] columns, against a terminal [termWidth] wide. The background slices
/// to the left and right of the panel are passed through [styleBarrier] (which
/// receives the plain-text slice). When [barrierNone] is true the background is
/// left styled as-is; otherwise it is restyled via [styleBarrier].
///
/// This is the shared centered-overlay row compositor used by the floating
/// panel modals. The overlay is always padded to [panelW] columns so the right
/// barrier slice lines up regardless of the overlay's intrinsic width.
String spliceOverlayRow(
  String bgLine,
  int leftCol,
  int panelW,
  String overlay,
  int termWidth, {
  required bool barrierNone,
  required String Function(String plain) styleBarrier,
}) {
  final bgVisible = visibleLength(bgLine);
  final paddedBg = bgVisible < termWidth
      ? '$bgLine${' ' * (termWidth - bgVisible)}'
      : bgLine;
  final safeLeft = leftCol.clamp(0, termWidth);
  final safeRight = (leftCol + panelW).clamp(0, termWidth);
  final beforeSlice = paddedBg.substring(
    0,
    ansiColumnToIndex(paddedBg, safeLeft),
  );
  final afterSlice = paddedBg.substring(ansiColumnToIndex(paddedBg, safeRight));
  final overlayPad = max(0, panelW - visibleLength(overlay));
  if (barrierNone) {
    return '$beforeSlice$overlay${' ' * overlayPad}$afterSlice';
  }
  final before = styleBarrier(stripAnsi(beforeSlice));
  final after = styleBarrier(stripAnsi(afterSlice));
  return '$before$overlay${' ' * overlayPad}$after';
}

/// Terminal column width of a single Unicode code point.
int charWidth(int cp) {
  // Zero-width: combining marks, variation selectors, joiners
  if ((cp >= 0x0300 && cp <= 0x036F) ||
      (cp >= 0x1AB0 && cp <= 0x1AFF) ||
      (cp >= 0x1DC0 && cp <= 0x1DFF) ||
      (cp >= 0x20D0 && cp <= 0x20FF) ||
      (cp >= 0xFE00 && cp <= 0xFE0F) ||
      (cp >= 0xFE20 && cp <= 0xFE2F) ||
      (cp >= 0xE0100 && cp <= 0xE01EF) ||
      cp == 0x200B ||
      cp == 0x200C ||
      cp == 0x200D ||
      cp == 0xFEFF) {
    return 0;
  }

  // Double-width: East Asian Wide/Fullwidth + Emoji
  if ((cp >= 0x1100 && cp <= 0x115F) ||
      (cp >= 0x231A && cp <= 0x231B) ||
      (cp >= 0x23E9 && cp <= 0x23F3) ||
      (cp >= 0x23F8 && cp <= 0x23FA) ||
      (cp >= 0x25FD && cp <= 0x25FE) ||
      (cp >= 0x2614 && cp <= 0x2615) ||
      (cp >= 0x2648 && cp <= 0x2653) ||
      cp == 0x267F ||
      cp == 0x2693 ||
      cp == 0x26A1 ||
      (cp >= 0x26AA && cp <= 0x26AB) ||
      (cp >= 0x26BD && cp <= 0x26BE) ||
      (cp >= 0x26C4 && cp <= 0x26C5) ||
      cp == 0x26CE ||
      cp == 0x26D4 ||
      cp == 0x26EA ||
      (cp >= 0x26F2 && cp <= 0x26F3) ||
      cp == 0x26F5 ||
      cp == 0x26FA ||
      cp == 0x26FD ||
      cp == 0x2702 ||
      cp == 0x2705 ||
      (cp >= 0x2708 && cp <= 0x270D) ||
      cp == 0x270F ||
      cp == 0x2712 ||
      cp == 0x2714 ||
      cp == 0x2716 ||
      cp == 0x271D ||
      cp == 0x2721 ||
      cp == 0x2728 ||
      (cp >= 0x2733 && cp <= 0x2734) ||
      cp == 0x2744 ||
      cp == 0x2747 ||
      cp == 0x274C ||
      cp == 0x274E ||
      (cp >= 0x2753 && cp <= 0x2755) ||
      cp == 0x2757 ||
      (cp >= 0x2763 && cp <= 0x2764) ||
      (cp >= 0x2795 && cp <= 0x2797) ||
      cp == 0x27A1 ||
      cp == 0x27B0 ||
      cp == 0x27BF ||
      (cp >= 0x2934 && cp <= 0x2935) ||
      (cp >= 0x2B05 && cp <= 0x2B07) ||
      (cp >= 0x2B1B && cp <= 0x2B1C) ||
      cp == 0x2B50 ||
      cp == 0x2B55 ||
      cp == 0x3030 ||
      cp == 0x303D ||
      cp == 0x3297 ||
      cp == 0x3299 ||
      (cp >= 0x2E80 && cp <= 0x303E) ||
      (cp >= 0x3040 && cp <= 0x33BF) ||
      (cp >= 0x3400 && cp <= 0x4DBF) ||
      (cp >= 0x4E00 && cp <= 0xA4CF) ||
      (cp >= 0xAC00 && cp <= 0xD7AF) ||
      (cp >= 0xF900 && cp <= 0xFAFF) ||
      (cp >= 0xFE10 && cp <= 0xFE19) ||
      (cp >= 0xFE30 && cp <= 0xFE6F) ||
      (cp >= 0xFF01 && cp <= 0xFF60) ||
      (cp >= 0xFFE0 && cp <= 0xFFE6) ||
      (cp >= 0x1F000 && cp <= 0x1FFFF) ||
      (cp >= 0x20000 && cp <= 0x3FFFF)) {
    return 2;
  }

  return 1;
}
