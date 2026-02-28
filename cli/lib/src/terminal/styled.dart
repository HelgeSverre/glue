/// Fluent ANSI string builder, accessible via `'text'.styled`.
///
/// Usage:
///   'Hello'.styled.bold.red          // bold red text
///   name.styled.bold                 // bold interpolation
///   'Warning'.styled.bgYellow.black  // black text on yellow bg
///   pixel.styled.rgb(r, g, b)       // 24-bit truecolor
///
/// Produces properly-nested ANSI sequences with specific close codes
/// (never raw `\x1b[0m` which resets all attributes).
class Styled {
  final String _text;
  final List<_AnsiPair> _styles;

  const Styled._(this._text, [this._styles = const []]);

  // -- Formatting ----------------------------------------------------------

  Styled get bold => _add('\x1b[1m', '\x1b[22m');
  Styled get dim => _add('\x1b[2m', '\x1b[22m');
  Styled get italic => _add('\x1b[3m', '\x1b[23m');
  Styled get underline => _add('\x1b[4m', '\x1b[24m');
  Styled get inverse => _add('\x1b[7m', '\x1b[27m');
  Styled get strikethrough => _add('\x1b[9m', '\x1b[29m');

  // -- Foreground colors (standard) ----------------------------------------

  Styled get black => _add('\x1b[30m', '\x1b[39m');
  Styled get red => _add('\x1b[31m', '\x1b[39m');
  Styled get green => _add('\x1b[32m', '\x1b[39m');
  Styled get yellow => _add('\x1b[33m', '\x1b[39m');
  Styled get blue => _add('\x1b[34m', '\x1b[39m');
  Styled get magenta => _add('\x1b[35m', '\x1b[39m');
  Styled get cyan => _add('\x1b[36m', '\x1b[39m');
  Styled get white => _add('\x1b[37m', '\x1b[39m');
  Styled get gray => _add('\x1b[90m', '\x1b[39m');

  // -- Foreground colors (bright) ------------------------------------------

  Styled get brightBlack => _add('\x1b[90m', '\x1b[39m');
  Styled get brightRed => _add('\x1b[91m', '\x1b[39m');
  Styled get brightGreen => _add('\x1b[92m', '\x1b[39m');
  Styled get brightYellow => _add('\x1b[93m', '\x1b[39m');
  Styled get brightBlue => _add('\x1b[94m', '\x1b[39m');
  Styled get brightMagenta => _add('\x1b[95m', '\x1b[39m');
  Styled get brightCyan => _add('\x1b[96m', '\x1b[39m');
  Styled get brightWhite => _add('\x1b[97m', '\x1b[39m');

  // -- Background colors (standard) ----------------------------------------

  Styled get bgBlack => _add('\x1b[40m', '\x1b[49m');
  Styled get bgRed => _add('\x1b[41m', '\x1b[49m');
  Styled get bgGreen => _add('\x1b[42m', '\x1b[49m');
  Styled get bgYellow => _add('\x1b[43m', '\x1b[49m');
  Styled get bgBlue => _add('\x1b[44m', '\x1b[49m');
  Styled get bgMagenta => _add('\x1b[45m', '\x1b[49m');
  Styled get bgCyan => _add('\x1b[46m', '\x1b[49m');
  Styled get bgWhite => _add('\x1b[47m', '\x1b[49m');

  // -- Background colors (bright) ------------------------------------------

  Styled get bgBrightBlack => _add('\x1b[100m', '\x1b[49m');
  Styled get bgBrightRed => _add('\x1b[101m', '\x1b[49m');
  Styled get bgBrightGreen => _add('\x1b[102m', '\x1b[49m');
  Styled get bgBrightYellow => _add('\x1b[103m', '\x1b[49m');
  Styled get bgBrightBlue => _add('\x1b[104m', '\x1b[49m');
  Styled get bgBrightMagenta => _add('\x1b[105m', '\x1b[49m');
  Styled get bgBrightCyan => _add('\x1b[106m', '\x1b[49m');
  Styled get bgBrightWhite => _add('\x1b[107m', '\x1b[49m');

  // -- Extended colors ------------------------------------------------------

  /// 256-color foreground. [n] is 0–255.
  Styled fg256(int n) => _add('\x1b[38;5;${n}m', '\x1b[39m');

  /// 256-color background. [n] is 0–255.
  Styled bg256(int n) => _add('\x1b[48;5;${n}m', '\x1b[49m');

  /// 24-bit RGB foreground.
  Styled rgb(int r, int g, int b) => _add('\x1b[38;2;$r;$g;${b}m', '\x1b[39m');

  /// 24-bit RGB background.
  Styled bgRgb(int r, int g, int b) =>
      _add('\x1b[48;2;$r;$g;${b}m', '\x1b[49m');

  // -- Internal -------------------------------------------------------------

  Styled _add(String open, String close) =>
      Styled._(_text, [..._styles, _AnsiPair(open, close)]);

  @override
  String toString() {
    if (_styles.isEmpty) return _text;
    final open = _styles.map((s) => s.open).join();
    final close = _styles.reversed.map((s) => s.close).join();
    return '$open$_text$close';
  }
}

class _AnsiPair {
  final String open;
  final String close;
  const _AnsiPair(this.open, this.close);
}

/// Entry point for the fluent builder.
extension StyledString on String {
  Styled get styled => Styled._(this);
}
