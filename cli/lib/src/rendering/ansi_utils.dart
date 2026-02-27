/// Strip all ANSI escape sequences from [text].
String stripAnsi(String text) {
  return text.replaceAll(RegExp(r'\x1b\[[0-9;]*[a-zA-Z]'), '');
}

/// Compute the visible column width of [text] in a terminal,
/// accounting for ANSI escapes, wide characters (emoji, CJK), and
/// zero-width characters (combining marks, variation selectors).
int visibleLength(String text) {
  final stripped = stripAnsi(text);
  var width = 0;
  for (final cp in stripped.runes) {
    width += _charWidth(cp);
  }
  return width;
}

/// Truncate [text] to [maxVisible] visible columns, preserving ANSI
/// sequences and handling wide characters. Appends '…' if truncated.
String ansiTruncate(String text, int maxVisible) {
  if (visibleLength(text) <= maxVisible) return text;
  final buf = StringBuffer();
  int visible = 0;
  final ansiPattern = RegExp(r'\x1b\[[0-9;]*[a-zA-Z]');
  var i = 0;
  while (i < text.length && visible < maxVisible - 1) {
    final match = ansiPattern.matchAsPrefix(text, i);
    if (match != null) {
      buf.write(match.group(0));
      i += match.group(0)!.length;
    } else {
      final codeUnit = text.codeUnitAt(i);
      int cp;
      int advance;
      if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && i + 1 < text.length) {
        final low = text.codeUnitAt(i + 1);
        cp = 0x10000 + ((codeUnit - 0xD800) << 10) + (low - 0xDC00);
        advance = 2;
      } else {
        cp = codeUnit;
        advance = 1;
      }
      final w = _charWidth(cp);
      if (w == 0) {
        buf.write(text.substring(i, i + advance));
        i += advance;
        continue;
      }
      if (visible + w > maxVisible - 1) break;
      buf.write(text.substring(i, i + advance));
      visible += w;
      i += advance;
    }
  }
  buf.write('…');
  return buf.toString();
}

/// Word-wrap [text] to fit within [maxWidth] visible columns.
/// Preserves ANSI sequences and existing newlines.
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

/// Terminal column width of a single Unicode code point.
int _charWidth(int cp) {
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
