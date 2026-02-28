import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Event types
// ---------------------------------------------------------------------------

/// Enumerates known special keys parsed from terminal input.
enum Key {
  escape,
  enter,
  backspace,
  tab,
  shiftTab,
  up,
  down,
  left,
  right,
  home,
  end,
  pageUp,
  pageDown,
  delete,
  ctrlA,
  ctrlC,
  ctrlD,
  ctrlE,
  ctrlK,
  ctrlL,
  ctrlU,
  ctrlW,
  unknown,
}

/// Base class for all terminal input events.
sealed class TerminalEvent {}

/// A recognised special-key press.
class KeyEvent extends TerminalEvent {
  final Key key;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final int? charCode;
  KeyEvent(this.key,
      {this.ctrl = false,
      this.alt = false,
      this.shift = false,
      this.charCode});

  @override
  String toString() =>
      'KeyEvent($key${ctrl ? ', ctrl' : ''}${alt ? ', alt' : ''}${shift ? ', shift' : ''})';
}

/// A printable character (may be multi-byte UTF-8).
class CharEvent extends TerminalEvent {
  final String char;
  final bool alt;
  CharEvent(this.char, {this.alt = false});

  @override
  String toString() => 'CharEvent($char${alt ? ', alt' : ''})';
}

/// The terminal was resized.
class ResizeEvent extends TerminalEvent {
  final int cols;
  final int rows;
  ResizeEvent(this.cols, this.rows);

  @override
  String toString() => 'ResizeEvent(${cols}x$rows)';
}

/// A mouse event (if mouse reporting is enabled).
class MouseEvent extends TerminalEvent {
  final int x;
  final int y;
  final int button;
  final bool isDown;
  MouseEvent(this.x, this.y, this.button, {this.isDown = true});

  /// Whether this is a scroll-wheel event (up or down).
  bool get isScroll => (button & 64) != 0;

  /// Whether the scroll direction is upward. Only meaningful when [isScroll] is true.
  bool get isScrollUp => isScroll && (button & 1) == 0;

  @override
  String toString() => 'MouseEvent($x, $y, button=$button, isDown=$isDown)';
}

/// Bracketed paste content from the terminal.
class PasteEvent extends TerminalEvent {
  final String content;
  PasteEvent(this.content);

  @override
  String toString() => 'PasteEvent(${content.length} chars)';
}

// ---------------------------------------------------------------------------
// ANSI styles
// ---------------------------------------------------------------------------

/// A pair of ANSI escape sequences that bracket styled text.
class AnsiStyle {
  final String open;
  final String close;
  const AnsiStyle(this.open, this.close);

  static const bold = AnsiStyle('\x1b[1m', '\x1b[22m');
  static const dim = AnsiStyle('\x1b[2m', '\x1b[22m');
  static const italic = AnsiStyle('\x1b[3m', '\x1b[23m');
  static const underline = AnsiStyle('\x1b[4m', '\x1b[24m');
  static const inverse = AnsiStyle('\x1b[7m', '\x1b[27m');
  static const red = AnsiStyle('\x1b[31m', '\x1b[39m');
  static const green = AnsiStyle('\x1b[32m', '\x1b[39m');
  static const yellow = AnsiStyle('\x1b[33m', '\x1b[39m');
  static const blue = AnsiStyle('\x1b[34m', '\x1b[39m');
  static const magenta = AnsiStyle('\x1b[35m', '\x1b[39m');
  static const cyan = AnsiStyle('\x1b[36m', '\x1b[39m');
  static const gray = AnsiStyle('\x1b[90m', '\x1b[39m');
}

// ---------------------------------------------------------------------------
// Terminal controller
// ---------------------------------------------------------------------------

/// Low-level terminal controller.
///
/// Takes over raw stdin/stdout, parses byte sequences into semantic
/// [TerminalEvent]s, and exposes ANSI helpers for cursor movement, styling,
/// and screen management.
class Terminal {
  final _inputController = StreamController<TerminalEvent>.broadcast();
  StreamSubscription<List<int>>? _stdinSub;
  StreamSubscription<ProcessSignal>? _sigwinchSub;
  bool _isRaw = false;
  List<int> _pending = [];
  Timer? _escTimer;
  bool _inPaste = false;
  List<int> _pasteBytes = [];

  /// Stream of parsed terminal input events.
  Stream<TerminalEvent> get events => _inputController.stream;

  /// Current terminal width in columns.
  int get columns => stdout.terminalColumns;

  /// Current terminal height in rows.
  int get rows => stdout.terminalLines;

  /// Whether the terminal is currently in raw mode.
  bool get isRaw => _isRaw;

  /// Guard all adds to [_inputController] against post-close calls.
  void _emit(TerminalEvent event) {
    if (!_inputController.isClosed) _inputController.add(event);
  }

  // ── Raw mode ────────────────────────────────────────────────────────────

  /// Enters raw mode — the terminal now owns every byte from stdin.
  void enableRawMode() {
    if (_isRaw) return;
    stdin.echoMode = false;
    stdin.lineMode = false;
    _isRaw = true;

    // Enable bracketed paste mode so we can distinguish pasted text.
    stdout.write('\x1b[?2004h');

    _stdinSub = stdin.listen(_parseInput);

    _sigwinchSub = ProcessSignal.sigwinch.watch().listen((_) {
      _emit(ResizeEvent(columns, rows));
    });
  }

  /// Restores normal terminal mode.
  void disableRawMode() {
    if (!_isRaw) return;
    // Disable bracketed paste mode before restoring terminal.
    stdout.write('\x1b[?2004l');
    stdin.echoMode = true;
    stdin.lineMode = true;
    _isRaw = false;
    _inPaste = false;
    _pasteBytes = [];
    _stdinSub?.cancel();
    _sigwinchSub?.cancel();
  }

  /// Releases all resources.
  void dispose() {
    _escTimer?.cancel();
    disableRawMode();
    _inputController.close();
  }

  // ── Input parsing ───────────────────────────────────────────────────────

  void _parseInput(List<int> bytes) {
    _escTimer?.cancel();
    _escTimer = null;
    final data = [..._pending, ...bytes];
    _pending = [];
    var i = 0;

    // If we're inside a bracketed paste, accumulate bytes until the
    // closing marker ESC[201~ arrives.
    if (_inPaste) {
      i = _accumulatePaste(data, 0);
      if (_inPaste) {
        // Still pasting — entire chunk consumed; wait for more.
        return;
      }
      // Paste ended; fall through to parse any remaining bytes.
    }

    while (i < data.length) {
      if (data[i] == 0x1b) {
        // If ESC is last byte, it might be start of a sequence — buffer
        // it briefly. If no follow-up arrives within 50ms, emit as
        // standalone Escape.
        if (i + 1 >= data.length) {
          _pending = data.sublist(i);
          _escTimer = Timer(const Duration(milliseconds: 50), () {
            if (_pending.isNotEmpty && _pending[0] == 0x1b) {
              _pending = _pending.sublist(1);
              _emit(KeyEvent(Key.escape));
              if (_pending.isNotEmpty) _parseInput([]);
            }
          });
          return;
        }
        if (data[i + 1] == 0x5b) {
          final (event, next, complete) = _parseCsiSafe(data, i + 2);
          if (!complete) {
            _pending = data.sublist(i);
            return;
          }
          if (event == null) {
            // Bracketed paste start — switch to paste accumulation mode.
            i = _accumulatePaste(data, next);
            if (_inPaste) return; // still pasting
            continue;
          }
          _emit(event);
          i = next;
          continue;
        }
        // ESC + CR (0x0d) = Shift+Enter (iTerm2 encoding)
        if (data[i + 1] == 0x0d) {
          _emit(KeyEvent(Key.enter, shift: true));
          i += 2;
          continue;
        }
        // ESC + LF (0x0a) = Shift+Enter (alternate iTerm2 encoding)
        if (data[i + 1] == 0x0a) {
          _emit(KeyEvent(Key.enter, shift: true));
          i += 2;
          continue;
        }
        // ESC + 0x7f = Alt+Backspace
        if (data[i + 1] == 0x7f) {
          _emit(KeyEvent(Key.backspace, alt: true));
          i += 2;
          continue;
        }
        // ESC + printable byte = Alt+char (e.g. Alt+f, Alt+b)
        if (data[i + 1] >= 0x20 && data[i + 1] < 0x7f) {
          _emit(CharEvent(String.fromCharCode(data[i + 1]), alt: true));
          i += 2;
          continue;
        }
        _emit(KeyEvent(Key.escape));
        i++;
      } else if (data[i] < 0x20 || data[i] == 0x7f) {
        _emit(_controlChar(data[i]));
        i++;
      } else {
        final (char, len, complete) = _decodeUtf8CharSafe(data, i);
        if (!complete) {
          _pending = data.sublist(i);
          return;
        }
        _emit(CharEvent(char));
        i += len;
      }
    }
  }

  /// Accumulate paste bytes starting at [start] in [data].
  /// Scans for the closing marker ESC[201~ and emits a PasteEvent when found.
  /// Returns the index after the consumed bytes.
  int _accumulatePaste(List<int> data, int start) {
    // Closing marker: ESC [ 2 0 1 ~ = [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e]
    const marker = [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e];
    for (var i = start; i < data.length; i++) {
      if (data[i] == 0x1b && i + marker.length <= data.length) {
        var found = true;
        for (var j = 0; j < marker.length; j++) {
          if (data[i + j] != marker[j]) {
            found = false;
            break;
          }
        }
        if (found) {
          // End of paste — emit everything accumulated so far.
          _pasteBytes.addAll(data.sublist(start, i));
          final content = utf8.decode(_pasteBytes, allowMalformed: true);
          _inPaste = false;
          _pasteBytes = [];
          _emit(PasteEvent(content));
          return i + marker.length;
        }
      }
      // If we might be at the start of an incomplete marker at the end
      // of data, buffer remaining bytes.
      if (data[i] == 0x1b && i + marker.length > data.length) {
        _pasteBytes.addAll(data.sublist(start, i));
        _pending = data.sublist(i);
        return data.length;
      }
    }
    // No marker found — accumulate everything.
    _pasteBytes.addAll(data.sublist(start));
    return data.length;
  }

  KeyEvent _controlChar(int byte) => switch (byte) {
        0x01 => KeyEvent(Key.ctrlA),
        0x03 => KeyEvent(Key.ctrlC, ctrl: true),
        0x04 => KeyEvent(Key.ctrlD, ctrl: true),
        0x05 => KeyEvent(Key.ctrlE),
        0x0a =>
          KeyEvent(Key.enter), // LF — some terminals send this instead of CR
        0x0b => KeyEvent(Key.ctrlK, ctrl: true),
        0x0c => KeyEvent(Key.ctrlL, ctrl: true),
        0x0d => KeyEvent(Key.enter),
        0x09 => KeyEvent(Key.tab),
        0x15 => KeyEvent(Key.ctrlU, ctrl: true),
        0x17 => KeyEvent(Key.ctrlW, ctrl: true),
        0x7f => KeyEvent(Key.backspace),
        _ => KeyEvent(Key.unknown, ctrl: true, charCode: byte),
      };

  /// Parse a CSI sequence starting after `ESC [`.
  /// Returns (event, nextIndex, complete). If [complete] is false, the
  /// sequence is incomplete and should be buffered for the next chunk.
  /// Returns null event to signal bracketed paste start (caller switches
  /// to paste accumulation mode).
  (TerminalEvent?, int, bool) _parseCsiSafe(List<int> bytes, int start) {
    var i = start;
    final params = StringBuffer();

    // Collect parameter bytes (digits, semicolons).
    while (i < bytes.length && (bytes[i] >= 0x30 && bytes[i] <= 0x3f)) {
      params.write(String.fromCharCode(bytes[i]));
      i++;
    }

    // Final byte — if we've run out of data, the sequence is incomplete.
    if (i >= bytes.length) {
      return (KeyEvent(Key.escape), i, false);
    }

    final finalByte = bytes[i];
    i++;

    final paramStr = params.toString();

    // SGR mouse: ESC [ < button;x;y M/m
    if (paramStr.startsWith('<') && (finalByte == 0x4d || finalByte == 0x6d)) {
      return (
        _parseSgrMouse(paramStr.substring(1), finalByte == 0x4d),
        i,
        true
      );
    }

    // CSI modifier encoding: "1;M" where M is 1+bitmask
    // (2=Shift, 3=Alt, 4=Shift+Alt, 5=Ctrl, etc).
    final parts = paramStr.split(';');
    final modifier = parts.length >= 2 ? (int.tryParse(parts.last) ?? 1) : 1;
    final isShift = (modifier - 1) & 0x01 != 0;
    final isAlt = (modifier - 1) & 0x02 != 0;
    final isCtrl = (modifier - 1) & 0x04 != 0;

    final TerminalEvent? event = switch (finalByte) {
      0x41 => KeyEvent(Key.up, alt: isAlt, ctrl: isCtrl, shift: isShift),
      0x42 => KeyEvent(Key.down, alt: isAlt, ctrl: isCtrl, shift: isShift),
      0x43 => KeyEvent(Key.right, alt: isAlt, ctrl: isCtrl, shift: isShift),
      0x44 => KeyEvent(Key.left, alt: isAlt, ctrl: isCtrl, shift: isShift),
      0x48 => KeyEvent(Key.home, alt: isAlt, ctrl: isCtrl, shift: isShift),
      0x46 => KeyEvent(Key.end, alt: isAlt, ctrl: isCtrl, shift: isShift),
      0x5a => KeyEvent(Key.shiftTab), // CSI Z = Shift+Tab
      // CSI u: keycode;modifiers u (Kitty keyboard protocol)
      0x75 => _parseCsiU(paramStr),
      0x7e => _parseTilde(paramStr),
      _ => KeyEvent(Key.unknown, charCode: finalByte),
    };

    return (event, i, true);
  }

  /// Parse CSI u (Kitty keyboard protocol): ESC [ keycode;modifiers u
  TerminalEvent _parseCsiU(String paramStr) {
    final parts = paramStr.split(';');
    final keycode = int.tryParse(parts.first) ?? 0;
    final modifier = parts.length >= 2 ? (int.tryParse(parts[1]) ?? 1) : 1;
    final isShift = (modifier - 1) & 0x01 != 0;
    final isAlt = (modifier - 1) & 0x02 != 0;
    final isCtrl = (modifier - 1) & 0x04 != 0;

    return switch (keycode) {
      13 => KeyEvent(Key.enter,
          shift: isShift, alt: isAlt, ctrl: isCtrl),
      9 => KeyEvent(Key.tab,
          shift: isShift, alt: isAlt, ctrl: isCtrl),
      27 => KeyEvent(Key.escape,
          shift: isShift, alt: isAlt, ctrl: isCtrl),
      127 => KeyEvent(Key.backspace,
          shift: isShift, alt: isAlt, ctrl: isCtrl),
      _ => keycode >= 32 && keycode < 127
          ? CharEvent(String.fromCharCode(keycode), alt: isAlt)
          : KeyEvent(Key.unknown, charCode: keycode),
    };
  }

  /// Parse SGR mouse: params = "button;x;y", isPress distinguishes M vs m.
  TerminalEvent _parseSgrMouse(String params, bool isPress) {
    final parts = params.split(';');
    if (parts.length < 3) return KeyEvent(Key.unknown);
    final button = int.tryParse(parts[0]) ?? 0;
    final x = int.tryParse(parts[1]) ?? 0;
    final y = int.tryParse(parts[2]) ?? 0;
    return MouseEvent(x, y, button, isDown: isPress);
  }

  /// Parse tilde-terminated CSI sequences.
  ///
  /// Handles standard keys (Delete, Page Up/Down) and the xterm
  /// modifyOtherKeys format: ESC[27;modifier;keycode~
  /// Also detects bracketed paste start (ESC[200~) — returns null to
  /// signal paste mode.
  TerminalEvent? _parseTilde(String params) {
    final parts = params.split(';');

    // Bracketed paste start: ESC[200~
    if (parts.first == '200') {
      _inPaste = true;
      _pasteBytes = [];
      return null; // signal paste mode to caller
    }

    // xterm modifyOtherKeys: ESC[27;modifier;keycode~
    if (parts.length == 3 && parts[0] == '27') {
      final modifier = int.tryParse(parts[1]) ?? 1;
      final keycode = int.tryParse(parts[2]) ?? 0;
      final isShift = (modifier - 1) & 0x01 != 0;
      final isAlt = (modifier - 1) & 0x02 != 0;
      final isCtrl = (modifier - 1) & 0x04 != 0;

      return switch (keycode) {
        13 => KeyEvent(Key.enter,
            shift: isShift, alt: isAlt, ctrl: isCtrl),
        9 => KeyEvent(Key.tab,
            shift: isShift, alt: isAlt, ctrl: isCtrl),
        27 => KeyEvent(Key.escape,
            shift: isShift, alt: isAlt, ctrl: isCtrl),
        127 => KeyEvent(Key.backspace,
            shift: isShift, alt: isAlt, ctrl: isCtrl),
        _ => keycode >= 32 && keycode < 127
            ? CharEvent(String.fromCharCode(keycode), alt: isAlt)
            : KeyEvent(Key.unknown, charCode: keycode),
      };
    }

    return switch (parts.first) {
      '3' => KeyEvent(Key.delete),
      '5' => KeyEvent(Key.pageUp),
      '6' => KeyEvent(Key.pageDown),
      _ => KeyEvent(Key.unknown),
    };
  }

  /// Decode a single UTF-8 character starting at [offset].
  /// Returns (character, bytesConsumed, complete). If [complete] is false,
  /// there aren't enough bytes yet and the caller should buffer.
  (String, int, bool) _decodeUtf8CharSafe(List<int> bytes, int offset) {
    final first = bytes[offset];
    int len;
    if (first < 0x80) {
      len = 1;
    } else if (first < 0xe0) {
      len = 2;
    } else if (first < 0xf0) {
      len = 3;
    } else {
      len = 4;
    }

    if (offset + len > bytes.length) {
      return ('', 0, false);
    }

    final charBytes = bytes.sublist(offset, offset + len);
    final decoded = utf8.decode(charBytes, allowMalformed: true);
    return (decoded, len, true);
  }

  // ── ANSI output helpers ─────────────────────────────────────────────────

  /// Writes raw text to stdout.
  void write(String s) => stdout.write(s);

  /// Moves the cursor to (1-indexed) [row], [col].
  void moveTo(int row, int col) => write('\x1b[$row;${col}H');

  /// Clears the entire screen.
  void clearScreen() => write('\x1b[2J');

  /// Clears the current line.
  void clearLine() => write('\x1b[2K');

  /// Hides the cursor.
  void hideCursor() => write('\x1b[?25l');

  /// Shows the cursor.
  void showCursor() => write('\x1b[?25h');

  /// Saves the cursor position (DEC private).
  void saveCursor() => write('\x1b7');

  /// Restores the cursor position (DEC private).
  void restoreCursor() => write('\x1b8');

  /// Enters the alternate screen buffer.
  void enableAltScreen() => write('\x1b[?1049h');

  /// Leaves the alternate screen buffer.
  void disableAltScreen() => write('\x1b[?1049l');

  /// Enables mouse reporting (X10 + SGR extended).
  void enableMouse() => write('\x1b[?1000h\x1b[?1006h');

  /// Disables mouse reporting.
  void disableMouse() => write('\x1b[?1000l\x1b[?1006l');

  /// Sets the hardware scroll region to rows [top] through [bottom] (1-indexed).
  void setScrollRegion(int top, int bottom) => write('\x1b[$top;${bottom}r');

  /// Resets the scroll region to the full terminal height.
  void resetScrollRegion() => write('\x1b[r');

  /// Writes [text] wrapped in the given ANSI [style].
  void writeStyled(String text, {AnsiStyle? style}) {
    if (style != null) {
      write('${style.open}$text${style.close}');
    } else {
      write(text);
    }
  }
}
