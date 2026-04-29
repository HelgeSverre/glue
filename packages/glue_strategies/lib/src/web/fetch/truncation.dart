class TokenTruncation {
  static const int _charsPerToken = 4;

  static int estimateTokens(String text) =>
      (text.length / _charsPerToken).ceil();

  static String truncate(String content, {required int maxTokens}) {
    final maxChars = maxTokens * _charsPerToken;
    if (content.length <= maxChars) return content;

    final paragraphs = content.split('\n\n');
    final buf = StringBuffer();
    var charCount = 0;

    for (final p in paragraphs) {
      if (charCount + p.length + 2 > maxChars && charCount > 0) break;
      if (charCount > 0) buf.write('\n\n');
      buf.write(p);
      charCount += p.length + 2;
    }

    final estimated = estimateTokens(buf.toString());
    buf.write('\n\n---\n(truncated to ~$estimated tokens)');
    return buf.toString();
  }
}
