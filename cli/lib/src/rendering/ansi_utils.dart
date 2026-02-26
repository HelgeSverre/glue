/// Strip all ANSI escape sequences from [text].
String stripAnsi(String text) {
  return text.replaceAll(RegExp(r'\x1b\[[0-9;]*[a-zA-Z]'), '');
}

/// Compute the visible length of [text] (ignoring ANSI escape sequences).
int visibleLength(String text) {
  return stripAnsi(text).length;
}

/// Truncate [text] to [maxVisible] visible characters, preserving ANSI sequences.
/// Appends '…' if truncated.
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
      buf.write(text[i]);
      visible++;
      i++;
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
